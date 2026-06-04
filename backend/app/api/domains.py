import gzip
from datetime import datetime

from fastapi import APIRouter, Query, Response
from sqlalchemy import select

from app.cache import redis_client
from app.config import settings
from app.deps import DbSession
from app.models import Domain
from app.schemas.domain import DomainListResponse, UpdatedAtResponse

router = APIRouter(prefix="/domains", tags=["domains"])


async def _cached_meta() -> tuple[datetime | None, int]:
    raw_updated, raw_count = await redis_client.mget(
        settings.cache_key_domains_updated_at, settings.cache_key_domains_count
    )
    updated_at = datetime.fromisoformat(raw_updated.decode()) if raw_updated else None
    count = int(raw_count) if raw_count else 0
    return updated_at, count


@router.get("/list", response_model=DomainListResponse)
async def list_domains(
    db: DbSession,
    limit: int = Query(default=1000, ge=1, le=50000),
    offset: int = Query(default=0, ge=0),
) -> DomainListResponse:
    """Постраничный список доменов (для отладки/админки). Для синка используйте /export."""
    rows = (
        await db.execute(
            select(Domain.domain).order_by(Domain.domain).limit(limit).offset(offset)
        )
    ).scalars().all()
    updated_at, count = await _cached_meta()
    return DomainListResponse(count=count, updated_at=updated_at, domains=list(rows))


@router.get("/export")
async def export_domains() -> Response:
    """Полный список доменов одним gzip-снимком (атомарный, всегда цельный)."""
    blob = await redis_client.get(settings.cache_key_domains_export)
    if blob is None:
        # Снимок ещё не собран — отдаём пустой валидный gzip.
        blob = gzip.compress(b"")
    updated_at, count = await _cached_meta()
    headers = {
        "Content-Encoding": "gzip",
        "Content-Type": "text/plain; charset=utf-8",
        "X-Domains-Count": str(count),
    }
    if updated_at:
        headers["X-Domains-Updated-At"] = updated_at.isoformat()
        headers["Last-Modified"] = updated_at.strftime("%a, %d %b %Y %H:%M:%S GMT")
    return Response(content=blob, headers=headers)


@router.get("/export.srs")
async def export_ruleset() -> Response:
    """Бинарный rule-set sing-box (.srs) со всеми доменами — расширение читает его напрямую.

    Предкомпилированный бинарь вместо source-JSON: разбор 127k доменов из JSON даёт
    мгновенный пик памяти и фатальный jetsam-kill в iOS-расширении (~50 МБ лимит).
    """
    blob = await redis_client.get(settings.cache_key_domains_srs)
    if blob is None:
        return Response(status_code=503, content=b"rule-set not built yet")
    updated_at, count = await _cached_meta()
    headers = {
        "Content-Type": "application/octet-stream",
        "X-Domains-Count": str(count),
    }
    if updated_at:
        headers["X-Domains-Updated-At"] = updated_at.isoformat()
        headers["Last-Modified"] = updated_at.strftime("%a, %d %b %Y %H:%M:%S GMT")
    return Response(content=blob, headers=headers)


@router.get("/export-ip.srs")
async def export_ip_ruleset() -> Response:
    """Бинарный IP rule-set (.srs) для сервисов без домена/SNI (Telegram MTProto).

    Доменный split не ловит трафик, идущий прямо на IP (без DNS/SNI), поэтому такие
    подсети маршрутизируются отдельным rule-set по destination IP.
    """
    blob = await redis_client.get(settings.cache_key_ip_srs)
    if blob is None:
        return Response(status_code=503, content=b"ip rule-set not built yet")
    raw_updated, raw_count = await redis_client.mget(
        settings.cache_key_ip_updated_at, settings.cache_key_ip_count
    )
    headers = {
        "Content-Type": "application/octet-stream",
        "X-IP-Count": raw_count.decode() if raw_count else "0",
    }
    if raw_updated:
        updated_at = datetime.fromisoformat(raw_updated.decode())
        headers["X-IP-Updated-At"] = updated_at.isoformat()
        headers["Last-Modified"] = updated_at.strftime("%a, %d %b %Y %H:%M:%S GMT")
    return Response(content=blob, headers=headers)


@router.get("/updated_at", response_model=UpdatedAtResponse)
async def domains_updated_at() -> UpdatedAtResponse:
    """Время последнего обновления и размер списка — для проверки клиентом."""
    updated_at, count = await _cached_meta()
    return UpdatedAtResponse(updated_at=updated_at, count=count)
