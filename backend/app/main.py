import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.api import admin, domains, proxy
from app.cache import redis_client
from app.config import settings
from app.ratelimit import limiter
from app.scheduler import start_scheduler, stop_scheduler
from app.services.domain_updater import (
    rebuild_snapshot_from_db,
    update_domains,
    update_ip_ruleset,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

_background_tasks: set[asyncio.Task] = set()


async def _initial_domain_fetch() -> None:
    try:
        count = await update_domains()
        logger.info("Initial domain fetch complete: %d domains", count)
    except Exception:
        logger.exception("Initial domain fetch failed; scheduler will retry")


async def _initial_ip_ruleset() -> None:
    try:
        count = await update_ip_ruleset()
        logger.info("Initial IP rule-set build complete: %d CIDRs", count)
    except Exception:
        logger.exception("Initial IP rule-set build failed; scheduler will retry")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Восстановить gzip-снимок доменов из БД, если он есть (после рестарта).
    count = 0
    try:
        count = await rebuild_snapshot_from_db()
        if count:
            logger.info("Restored domains snapshot from DB: %d domains", count)
    except Exception:
        logger.exception("Failed to restore domains snapshot on startup")

    # Если доменов ещё нет — подтянуть их сразу в фоне, не блокируя старт.
    if count == 0:
        logger.info("No domains yet; starting initial fetch in background")
        task = asyncio.create_task(_initial_domain_fetch())
        _background_tasks.add(task)
        task.add_done_callback(_background_tasks.discard)

    # IP rule-set (Telegram) в Redis не персистится — собираем при старте в фоне.
    ip_task = asyncio.create_task(_initial_ip_ruleset())
    _background_tasks.add(ip_task)
    ip_task.add_done_callback(_background_tasks.discard)

    start_scheduler()
    yield
    stop_scheduler()
    await redis_client.aclose()


app = FastAPI(title=settings.app_name, version="1.0", lifespan=lifespan)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.include_router(domains.router)
app.include_router(proxy.router)
app.include_router(admin.router)


@app.get("/health", tags=["health"])
async def health() -> dict:
    try:
        await redis_client.ping()
        redis_ok = True
    except Exception:
        redis_ok = False
    return {"status": "ok", "redis": redis_ok}
