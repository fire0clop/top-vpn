import pytest

from app.services import domain_updater


def test_normalize_domains():
    raw = "\n".join(
        [
            "# comment",
            "YouTube.com",
            "www.instagram.com",
            "*.telegram.org",
            "ozon.ru ; extra",
            "",
            "not a domain!!",
            "trailing.dot.",
        ]
    )
    result = domain_updater.normalize_domains(raw)
    assert "youtube.com" in result
    assert "instagram.com" in result  # www. stripped
    assert "telegram.org" in result  # *. stripped
    assert "ozon.ru" in result
    assert "trailing.dot" in result
    assert "not a domain!!" not in result


@pytest.mark.asyncio
async def test_update_and_export_flow(app_client, monkeypatch):
    async def fake_fetch_domains():
        return {"youtube.com", "instagram.com", "telegram.org"}, "antizapret"

    monkeypatch.setattr(domain_updater, "fetch_domains", fake_fetch_domains)

    # Register an admin user directly via DB session.
    from app.security import hash_password

    sm = domain_updater.async_session_maker
    from app.models import User

    async with sm() as db:
        db.add(
            User(
                email="admin@example.com",
                password_hash=hash_password("supersecret1"),
                is_admin=True,
            )
        )
        await db.commit()

    login = await app_client.post(
        "/auth/login", json={"email": "admin@example.com", "password": "supersecret1"}
    )
    token = login.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    r = await app_client.post("/admin/domains/refresh", headers=headers)
    assert r.status_code == 200, r.text
    assert r.json()["domains_count"] == 3

    meta = await app_client.get("/domains/updated_at", headers=headers)
    assert meta.json()["count"] == 3
    assert meta.json()["updated_at"] is not None

    export = await app_client.get("/domains/export", headers=headers)
    assert export.status_code == 200
    # httpx auto-decompresses gzip via Content-Encoding; read decoded text.
    text = export.text
    assert "youtube.com" in text
    assert "telegram.org" in text


@pytest.mark.asyncio
async def test_non_admin_cannot_refresh(app_client):
    await app_client.post(
        "/auth/register", json={"email": "plain@example.com", "password": "supersecret1"}
    )
    login = await app_client.post(
        "/auth/login", json={"email": "plain@example.com", "password": "supersecret1"}
    )
    token = login.json()["access_token"]
    r = await app_client.post(
        "/admin/domains/refresh", headers={"Authorization": f"Bearer {token}"}
    )
    assert r.status_code == 403
