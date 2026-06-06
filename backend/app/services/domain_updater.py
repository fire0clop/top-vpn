"""Загрузка и атомарное обновление списка заблокированных доменов.

Алгоритм (ТЗ 3.4):
1. Скачать список из основного источника (antizapret), при ошибке — из резервного (РКН).
2. Нормализовать домены (lowercase, убрать www., отбросить мусор).
3. Транзакционно заменить таблицу domains в PostgreSQL.
4. Собрать gzip-снимок полного списка и атомарно записать в Redis.
5. Записать запись в update_log.

Атомарность отдачи: экспорт читает готовый gzip-снимок из Redis. Пока новый
снимок не собран и не записан одной операцией SET, клиенты получают предыдущий
снимок целиком — без пустых или наполовину обновлённых списков, без обрывов VPN.
"""

import asyncio
import gzip
import ipaddress
import json
import logging
import re
import subprocess
import tempfile
from datetime import UTC, datetime
from pathlib import Path

import httpx
from sqlalchemy import delete, func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.cache import redis_client
from app.config import settings
from app.database import async_session_maker
from app.models import Domain, UpdateLog

logger = logging.getLogger(__name__)

_DOMAIN_RE = re.compile(r"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$")


def normalize_domains(raw: str) -> set[str]:
    """Привести сырой текст к набору валидных доменов."""
    result: set[str] = set()
    for line in raw.splitlines():
        candidate = line.strip().lower()
        if not candidate or candidate.startswith(("#", "//")):
            continue
        # antizapret отдаёт по одному домену в строке; РКН — CSV, домен может быть
        # в отдельном поле. Берём первый непустой токен по разделителям ; и пробелам.
        candidate = re.split(r"[;,\s]", candidate, maxsplit=1)[0]
        if candidate.startswith("*."):
            candidate = candidate[2:]
        if candidate.startswith("www."):
            candidate = candidate[4:]
        candidate = candidate.rstrip(".")
        if _DOMAIN_RE.match(candidate):
            result.add(candidate)
    return result


async def _fetch(url: str) -> str:
    async with httpx.AsyncClient(timeout=settings.domain_fetch_timeout_seconds) as client:
        response = await client.get(url, follow_redirects=True)
        response.raise_for_status()
        return response.text


async def fetch_domains() -> tuple[set[str], str]:
    """Скачать домены: основной источник, при сбое — резервный."""
    try:
        raw = await _fetch(settings.domains_primary_url)
        domains = normalize_domains(raw)
        if domains:
            return domains, "antizapret"
        logger.warning("Primary domains source returned no valid domains, trying fallback")
    except (httpx.HTTPError, httpx.TimeoutException) as exc:
        logger.warning("Primary domains source failed: %s, trying fallback", exc)

    raw = await _fetch(settings.domains_fallback_url)
    return normalize_domains(raw), "rkn"


async def _replace_domains(db: AsyncSession, domains: set[str], source: str) -> None:
    """Транзакционно заменить содержимое таблицы domains."""
    await db.execute(delete(Domain))
    if domains:
        rows = [{"domain": d, "source": source} for d in domains]
        # Чанками, чтобы не упереться в лимит параметров.
        for start in range(0, len(rows), 5000):
            chunk = rows[start : start + 5000]
            await db.execute(pg_insert(Domain).on_conflict_do_nothing(), chunk)


def _compile_srs_sync(source: dict) -> bytes:
    """Скомпилировать source-rule-set в бинарный .srs через CLI sing-box.

    Расширение читает rule-set в формате `binary` (предкомпилированный): разбор
    source-JSON со 127k доменов даёт мгновенный пик памяти и фатальный jetsam-kill на
    iOS (~50 МБ лимит). Компилируем на сервере той же версией sing-box, что и libbox.
    """
    with tempfile.TemporaryDirectory() as tmp:
        src_path = Path(tmp) / "rules.json"
        out_path = Path(tmp) / "rules.srs"
        src_path.write_text(json.dumps(source), encoding="utf-8")
        subprocess.run(
            [settings.sing_box_bin, "rule-set", "compile", "--output", str(out_path), str(src_path)],
            check=True,
            capture_output=True,
        )
        return out_path.read_bytes()


async def _compile_srs(source: dict) -> bytes | None:
    """Скомпилировать .srs во вспомогательном потоке. None — если CLI недоступен."""
    try:
        return await asyncio.to_thread(_compile_srs_sync, source)
    except FileNotFoundError:
        logger.warning("sing-box CLI not found at %s; skipping .srs build", settings.sing_box_bin)
    except subprocess.CalledProcessError as exc:
        logger.error("sing-box rule-set compile failed: %s", exc.stderr.decode(errors="replace"))
    return None


async def _publish_snapshot(domains: set[str], updated_at: datetime) -> None:
    """Собрать gzip-снимок и бинарный .srs, затем атомарно опубликовать в Redis.

    Оба артефакта компилируются до открытия транзакции, поэтому клиенты получают
    либо весь старый набор (текст + .srs), либо весь новый — без рассинхрона и обрывов.
    """
    # Всегда добавляем кастомные домены (YouTube и т.п.), которых нет в источниках.
    # Единая точка: переживает и update_domains, и rebuild_snapshot_from_db.
    domains = set(domains) | set(settings.extra_blocked_domains)
    payload = "\n".join(sorted(domains)).encode("utf-8")
    blob = gzip.compress(payload, compresslevel=6)
    srs = await _compile_srs({"version": 2, "rules": [{"domain_suffix": sorted(domains)}]})
    async with redis_client.pipeline(transaction=True) as pipe:
        pipe.set(settings.cache_key_domains_export, blob)
        if srs is not None:
            pipe.set(settings.cache_key_domains_srs, srs)
        pipe.set(settings.cache_key_domains_count, str(len(domains)))
        pipe.set(settings.cache_key_domains_updated_at, updated_at.isoformat())
        await pipe.execute()


async def update_domains() -> int:
    """Полный цикл обновления. Возвращает количество доменов."""
    domains, source = await fetch_domains()
    if not domains:
        logger.error("No domains fetched from any source; keeping previous snapshot")
        return 0

    updated_at = datetime.now(UTC)
    async with async_session_maker() as db:
        async with db.begin():
            await _replace_domains(db, domains, source)
            db.add(UpdateLog(source=source, domains_count=len(domains), updated_at=updated_at))

    # Снимок публикуем только после успешного коммита в БД.
    await _publish_snapshot(domains, updated_at)
    logger.info("Domains updated: %d domains from %s", len(domains), source)
    return len(domains)


async def rebuild_snapshot_from_db() -> int:
    """Восстановить Redis-снимок из БД (например, после рестарта без обновления)."""
    async with async_session_maker() as db:
        rows = (await db.execute(select(Domain.domain))).scalars().all()
        last_log = await db.scalar(select(UpdateLog).order_by(UpdateLog.updated_at.desc()).limit(1))
    if not rows:
        return 0
    updated_at = last_log.updated_at if last_log else datetime.now(UTC)
    await _publish_snapshot(set(rows), updated_at)
    return len(rows)


async def domains_count_in_db() -> int:
    async with async_session_maker() as db:
        return await db.scalar(select(func.count(Domain.id))) or 0


def normalize_cidrs(raw: str) -> list[str]:
    """Извлечь валидные CIDR-подсети из текста (по одной в строке)."""
    result: list[str] = []
    for line in raw.splitlines():
        candidate = line.strip()
        if not candidate or candidate.startswith("#"):
            continue
        try:
            result.append(str(ipaddress.ip_network(candidate, strict=False)))
        except ValueError:
            continue
    return result


async def update_ip_ruleset() -> int:
    """Собрать IP rule-set (.srs) для сервисов без домена/SNI и опубликовать в Redis.

    Сейчас это подсети Telegram: MTProto ходит прямо на IP дата-центров, доменный
    split его не ловит. Источник — официальный список Telegram, при сбое — фолбэк.
    """
    cidrs: list[str] = []
    try:
        raw = await _fetch(settings.telegram_cidr_url)
        cidrs = normalize_cidrs(raw)
    except (httpx.HTTPError, httpx.TimeoutException) as exc:
        logger.warning("Telegram CIDR source failed: %s, using fallback", exc)
    if not cidrs:
        cidrs = list(settings.ip_ruleset_fallback_cidrs)

    srs = await _compile_srs({"version": 2, "rules": [{"ip_cidr": cidrs}]})
    if srs is None:
        logger.error("IP rule-set compile failed; keeping previous snapshot")
        return 0

    updated_at = datetime.now(UTC)
    async with redis_client.pipeline(transaction=True) as pipe:
        pipe.set(settings.cache_key_ip_srs, srs)
        pipe.set(settings.cache_key_ip_count, str(len(cidrs)))
        pipe.set(settings.cache_key_ip_updated_at, updated_at.isoformat())
        await pipe.execute()
    logger.info("IP rule-set updated: %d CIDRs", len(cidrs))
    return len(cidrs)
