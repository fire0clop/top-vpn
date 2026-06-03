from datetime import datetime

from pydantic import BaseModel, ConfigDict


class DomainPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    domain: str
    source: str
    added_at: datetime


class DomainListResponse(BaseModel):
    count: int
    updated_at: datetime | None
    domains: list[str]


class UpdatedAtResponse(BaseModel):
    updated_at: datetime | None
    count: int
