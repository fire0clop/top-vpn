import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger

from app.config import settings
from app.services.domain_updater import update_domains, update_ip_ruleset
from app.services.proxy_checker import check_proxies

logger = logging.getLogger(__name__)

scheduler = AsyncIOScheduler(timezone="UTC")


async def _safe_update_domains() -> None:
    try:
        await update_domains()
    except Exception:
        logger.exception("Scheduled domain update failed")


async def _safe_check_proxies() -> None:
    try:
        await check_proxies()
    except Exception:
        logger.exception("Scheduled proxy check failed")


async def _safe_update_ip_ruleset() -> None:
    try:
        await update_ip_ruleset()
    except Exception:
        logger.exception("Scheduled IP rule-set update failed")


def start_scheduler() -> None:
    scheduler.add_job(
        _safe_update_domains,
        trigger=IntervalTrigger(hours=settings.domains_update_interval_hours),
        id="update_domains",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
    )
    scheduler.add_job(
        _safe_update_ip_ruleset,
        trigger=IntervalTrigger(hours=settings.ip_ruleset_update_interval_hours),
        id="update_ip_ruleset",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
    )
    scheduler.add_job(
        _safe_check_proxies,
        trigger=IntervalTrigger(minutes=settings.proxy_check_interval_minutes),
        id="check_proxies",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
    )
    scheduler.start()
    logger.info("Scheduler started")


def stop_scheduler() -> None:
    if scheduler.running:
        scheduler.shutdown(wait=False)
