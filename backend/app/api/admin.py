from fastapi import APIRouter, status

from app.deps import DbSession
from app.models import ProxyServer
from app.schemas.proxy import ProxyServerCreate, ProxyServerPublic
from app.services.domain_updater import update_domains

router = APIRouter(prefix="/admin", tags=["admin"])


@router.post("/domains/refresh")
async def refresh_domains() -> dict:
    """Принудительно обновить список доменов из источников."""
    count = await update_domains()
    return {"status": "ok", "domains_count": count}


@router.post("/proxy/add", response_model=ProxyServerPublic, status_code=status.HTTP_201_CREATED)
async def add_proxy(payload: ProxyServerCreate, db: DbSession) -> ProxyServer:
    proxy = ProxyServer(
        host=payload.host,
        port=payload.port,
        protocol=payload.protocol,
        region=payload.region,
        username=payload.username,
        password=payload.password,
        uuid=payload.uuid,
        flow=payload.flow,
        public_key=payload.public_key,
        short_id=payload.short_id,
        server_name=payload.server_name,
        expires_at=payload.expires_at,
    )
    db.add(proxy)
    await db.commit()
    await db.refresh(proxy)
    return proxy
