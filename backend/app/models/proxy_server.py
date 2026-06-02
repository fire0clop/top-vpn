from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class ProxyServer(Base):
    __tablename__ = "proxy_servers"

    id: Mapped[int] = mapped_column(primary_key=True)
    host: Mapped[str] = mapped_column(String(255), nullable=False)
    port: Mapped[int] = mapped_column(Integer, nullable=False)
    protocol: Mapped[str] = mapped_column(String(32), default="vless", nullable=False)
    region: Mapped[str] = mapped_column(String(64), nullable=False)
    username: Mapped[str | None] = mapped_column(String(255), nullable=True)
    password: Mapped[str | None] = mapped_column(String(255), nullable=True)
    # VLESS+Reality (заполняются для protocol="vless")
    uuid: Mapped[str | None] = mapped_column(String(64), nullable=True)
    flow: Mapped[str | None] = mapped_column(String(32), nullable=True)
    public_key: Mapped[str | None] = mapped_column(String(128), nullable=True)
    short_id: Mapped[str | None] = mapped_column(String(32), nullable=True)
    server_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    latency_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    last_checked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
