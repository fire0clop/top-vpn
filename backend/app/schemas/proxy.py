from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class ProxyServerPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    host: str
    port: int
    protocol: str
    region: str
    username: str | None
    password: str | None
    uuid: str | None
    flow: str | None
    public_key: str | None
    short_id: str | None
    server_name: str | None
    is_active: bool
    latency_ms: int | None
    last_checked_at: datetime | None
    expires_at: datetime | None


class ProxyServerCreate(BaseModel):
    host: str = Field(min_length=1, max_length=255)
    port: int = Field(ge=1, le=65535)
    protocol: str = "vless"
    region: str = Field(min_length=1, max_length=64)
    username: str | None = Field(default=None, max_length=255)
    password: str | None = Field(default=None, max_length=255)
    uuid: str | None = Field(default=None, max_length=64)
    flow: str | None = Field(default=None, max_length=32)
    public_key: str | None = Field(default=None, max_length=128)
    short_id: str | None = Field(default=None, max_length=32)
    server_name: str | None = Field(default=None, max_length=255)
    expires_at: datetime | None = None
