from datetime import datetime

from sqlalchemy import DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Domain(Base):
    __tablename__ = "domains"

    id: Mapped[int] = mapped_column(primary_key=True)
    domain: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    source: Mapped[str] = mapped_column(String(64), default="antizapret", nullable=False)
    added_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
