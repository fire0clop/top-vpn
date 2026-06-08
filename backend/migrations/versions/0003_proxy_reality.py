"""proxy vless+reality fields

Revision ID: 0003_proxy_reality
Revises: 0002_proxy_credentials
Create Date: 2026-05-31

"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0003_proxy_reality"
down_revision: str | None = "0002_proxy_credentials"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("proxy_servers", sa.Column("uuid", sa.String(length=64), nullable=True))
    op.add_column("proxy_servers", sa.Column("flow", sa.String(length=32), nullable=True))
    op.add_column("proxy_servers", sa.Column("public_key", sa.String(length=128), nullable=True))
    op.add_column("proxy_servers", sa.Column("short_id", sa.String(length=32), nullable=True))
    op.add_column("proxy_servers", sa.Column("server_name", sa.String(length=255), nullable=True))


def downgrade() -> None:
    op.drop_column("proxy_servers", "server_name")
    op.drop_column("proxy_servers", "short_id")
    op.drop_column("proxy_servers", "public_key")
    op.drop_column("proxy_servers", "flow")
    op.drop_column("proxy_servers", "uuid")
