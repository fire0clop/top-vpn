from collections.abc import AsyncGenerator

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

import fakeredis.aioredis  # type: ignore


@pytest_asyncio.fixture
async def app_client(monkeypatch) -> AsyncGenerator[AsyncClient, None]:
    # In-memory SQLite + fake Redis so tests need no external services.
    import app.cache as cache_module
    import app.database as database_module

    test_engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    test_sessionmaker = async_sessionmaker(
        test_engine, class_=AsyncSession, expire_on_commit=False
    )

    from app.database import Base
    import app.models  # noqa: F401

    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    fake_redis = fakeredis.aioredis.FakeRedis(decode_responses=False)

    monkeypatch.setattr(database_module, "async_session_maker", test_sessionmaker)
    monkeypatch.setattr(cache_module, "redis_client", fake_redis)

    # Patch references already imported into modules.
    import app.deps as deps_module
    import app.api.domains as domains_api
    import app.api.stats as stats_api
    import app.services.domain_updater as updater

    async def _get_db():
        async with test_sessionmaker() as session:
            yield session

    monkeypatch.setattr(updater, "async_session_maker", test_sessionmaker)
    monkeypatch.setattr(updater, "redis_client", fake_redis)
    monkeypatch.setattr(domains_api, "redis_client", fake_redis)
    monkeypatch.setattr(stats_api, "redis_client", fake_redis)

    from app.database import get_db
    from app.main import app
    from app.ratelimit import limiter

    limiter.enabled = False
    app.dependency_overrides[get_db] = _get_db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client

    app.dependency_overrides.clear()
    await test_engine.dispose()
