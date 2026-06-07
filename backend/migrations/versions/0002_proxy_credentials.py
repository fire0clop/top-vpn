"""proxy credentials and expiry

Revision ID: 0002_proxy_credentials
Revises: 0001_initial
Create Date: 2026-05-30

"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0002_proxy_credentials"
down_revision: str | None = "0001_initial"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("proxy_servers", sa.Column("username", sa.String(length=255), nullable=True))
    op.add_column("proxy_servers", sa.Column("password", sa.String(length=255), nullable=True))
    op.add_column(
        "proxy_servers", sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("proxy_servers", "expires_at")
    op.drop_column("proxy_servers", "password")
    op.drop_column("proxy_servers", "username")
