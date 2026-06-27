"""Завести/обновить VLESS+Reality прокси и деактивировать мёртвые SOCKS5.

Запуск: python -m scripts.seed_proxy
Идемпотентно: ищет сервер по host, обновляет либо создаёт.
"""

import asyncio

from sqlalchemy import delete, select

from app.database import async_session_maker
from app.models import ProxyServer

# NOTE: placeholder values — replace with your own VLESS+Reality node before running.
# Real production credentials were removed prior to open-sourcing this repo.
SERVER = {
    "host": "YOUR_SERVER_HOST",              # e.g. "203.0.113.10"
    "port": 443,
    "protocol": "vless",
    "region": "Germany",
    "uuid": "00000000-0000-0000-0000-000000000000",  # VLESS client UUID
    "flow": "xtls-rprx-vision",
    "public_key": "YOUR_REALITY_PUBLIC_KEY",
    "short_id": "YOUR_REALITY_SHORT_ID",
    "server_name": "www.microsoft.com",       # Reality SNI / masquerade domain
}


async def main() -> None:
    async with async_session_maker() as db:
        # Удалить старые SOCKS5-прокси: от этого транспорта отказались (палится DPI,
        # IP банится). Деактивации мало — proxy_checker реактивирует живой по TCP.
        old = (
            await db.execute(select(ProxyServer).where(ProxyServer.protocol == "socks5"))
        ).scalars().all()
        for p in old:
            print(f"Deleting old socks5 proxy {p.host}:{p.port}")
        await db.execute(delete(ProxyServer).where(ProxyServer.protocol == "socks5"))

        existing = await db.scalar(
            select(ProxyServer).where(ProxyServer.host == SERVER["host"])
        )
        if existing:
            for k, v in SERVER.items():
                setattr(existing, k, v)
            existing.is_active = True
            print(f"Updated VLESS proxy {SERVER['host']}")
        else:
            db.add(ProxyServer(**SERVER, is_active=True))
            print(f"Created VLESS proxy {SERVER['host']}")
        await db.commit()


if __name__ == "__main__":
    asyncio.run(main())
