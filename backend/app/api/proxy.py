from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import or_, select

from app.deps import DbSession
from app.models import ProxyServer
from app.schemas.proxy import ProxyServerPublic

router = APIRouter(prefix="/proxy", tags=["proxy"])


def _not_expired():
    now = datetime.now(UTC)
    return or_(ProxyServer.expires_at.is_(None), ProxyServer.expires_at > now)


@router.get("/list", response_model=list[ProxyServerPublic])
async def list_proxies(db: DbSession) -> list[ProxyServer]:
    rows = (
        await db.execute(
            select(ProxyServer)
            .where(ProxyServer.is_active.is_(True), _not_expired())
            .order_by(ProxyServer.region)
        )
    ).scalars().all()
    return list(rows)


@router.get("/best", response_model=ProxyServerPublic)
async def best_proxy(db: DbSession) -> ProxyServer:
    """Самый быстрый активный непротухший прокси (минимальная задержка)."""
    proxy = await db.scalar(
        select(ProxyServer)
        .where(
            ProxyServer.is_active.is_(True),
            ProxyServer.latency_ms.is_not(None),
            _not_expired(),
        )
        .order_by(ProxyServer.latency_ms.asc())
        .limit(1)
    )
    if proxy is None:
        # Фолбэк: любой активный непротухший, даже без замера задержки.
        proxy = await db.scalar(
            select(ProxyServer)
            .where(ProxyServer.is_active.is_(True), _not_expired())
            .limit(1)
        )
    if proxy is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="No active proxy available"
        )
    return proxy
