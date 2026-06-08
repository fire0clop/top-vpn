import pytest


@pytest.mark.asyncio
async def test_register_and_login(app_client):
    r = await app_client.post(
        "/auth/register", json={"email": "a@example.com", "password": "supersecret1"}
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["email"] == "a@example.com"
    assert body["is_admin"] is False

    r = await app_client.post(
        "/auth/login", json={"email": "a@example.com", "password": "supersecret1"}
    )
    assert r.status_code == 200, r.text
    tokens = r.json()
    assert tokens["access_token"]
    assert tokens["refresh_token"]


@pytest.mark.asyncio
async def test_duplicate_email_rejected(app_client):
    payload = {"email": "dup@example.com", "password": "supersecret1"}
    assert (await app_client.post("/auth/register", json=payload)).status_code == 201
    assert (await app_client.post("/auth/register", json=payload)).status_code == 409


@pytest.mark.asyncio
async def test_login_wrong_password(app_client):
    await app_client.post(
        "/auth/register", json={"email": "b@example.com", "password": "supersecret1"}
    )
    r = await app_client.post(
        "/auth/login", json={"email": "b@example.com", "password": "wrongpass1"}
    )
    assert r.status_code == 401


@pytest.mark.asyncio
async def test_refresh_rotates_token(app_client):
    await app_client.post(
        "/auth/register", json={"email": "c@example.com", "password": "supersecret1"}
    )
    login = await app_client.post(
        "/auth/login", json={"email": "c@example.com", "password": "supersecret1"}
    )
    refresh = login.json()["refresh_token"]

    r = await app_client.post("/auth/refresh", json={"refresh_token": refresh})
    assert r.status_code == 200, r.text
    new_refresh = r.json()["refresh_token"]
    assert new_refresh != refresh

    # Old refresh token must now be revoked.
    r2 = await app_client.post("/auth/refresh", json={"refresh_token": refresh})
    assert r2.status_code == 401


@pytest.mark.asyncio
async def test_protected_endpoint_requires_auth(app_client):
    r = await app_client.get("/domains/updated_at")
    assert r.status_code == 403  # no bearer credentials
