"""Проверка доступности прокси-серверов и измерение задержки (ТЗ 3.2)."""

import asyncio
import logging
import time
from datetime import UTC, datetime

from sqlalchemy import select

from app.config import settings
from app.database import async_session_maker
from app.models import ProxyServer

logger = logging.getLogger(__name__)


async def _measure_latency(host: str, port: int) -> int | None:
    """TCP-connect до прокси, вернуть задержку в мс либо None если недоступен."""
    start = time.perf_counter()
    try:
        fut = asyncio.open_connection(host, port)
        reader, writer = await asyncio.wait_for(fut, timeout=settings.proxy_check_timeout_seconds)
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass
        return int((time.perf_counter() - start) * 1000)
    except (OSError, asyncio.TimeoutError):
        return None


async def check_proxies() -> int:
    """Проверить все прокси, обновить latency_ms и is_active. Вернуть число живых."""
    async with async_session_maker() as db:
        proxies = (await db.execute(select(ProxyServer))).scalars().all()
        if not proxies:
            return 0
        results = await asyncio.gather(
            *(_measure_latency(p.host, p.port) for p in proxies)
        )
        now = datetime.now(UTC)
        alive = 0
        for proxy, latency in zip(proxies, results, strict=True):
            proxy.latency_ms = latency
            proxy.is_active = latency is not None
            proxy.last_checked_at = now
            if latency is not None:
                alive += 1
        await db.commit()
    logger.info("Proxy check done: %d/%d alive", alive, len(proxies))
    return alive
