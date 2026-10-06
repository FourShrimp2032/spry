import time
from types import SimpleNamespace

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from app import auth
from app.main import app

client = TestClient(app)
POOL = "us-east-1_TestPool"
ISSUER = f"https://cognito-idp.us-east-1.amazonaws.com/{POOL}"
KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
OTHER_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)


def token(key=KEY, **changes):
    claims = {
        "sub": "user-1",
        "iss": ISSUER,
        "client_id": "web-client",
        "token_use": "access",
        "exp": int(time.time()) + 300,
    } | changes
    return jwt.encode(claims, key, algorithm="RS256", headers={"kid": "test"})


@pytest.fixture
def protected(monkeypatch):
    monkeypatch.setenv("COGNITO_USER_POOL_ID", POOL)
    monkeypatch.setenv("COGNITO_REGION", "us-east-1")
    monkeypatch.setenv("COGNITO_CLIENT_ID", "web-client")
    keys = SimpleNamespace(get_signing_key_from_jwt=lambda _: SimpleNamespace(key=KEY.public_key()))
    monkeypatch.setattr(auth, "signing_keys", lambda issuer: keys)


def test_api_stays_public_without_a_user_pool(monkeypatch):
    monkeypatch.delenv("COGNITO_USER_POOL_ID", raising=False)
    assert client.get("/api/meetings").status_code == 200


@pytest.mark.usefixtures("protected")
def test_valid_access_token_is_accepted():
    response = client.get("/api/meetings", headers={"Authorization": f"Bearer {token()}"})
    assert response.status_code == 200


@pytest.mark.usefixtures("protected")
@pytest.mark.parametrize(
    "headers",
    [
        {},
        {"Authorization": "Basic abc"},
        {"Authorization": "Bearer not-a-jwt"},
        {"Authorization": f"Bearer {token(key=OTHER_KEY)}"},
        {"Authorization": f"Bearer {token(exp=int(time.time()) - 10)}"},
        {"Authorization": f"Bearer {token(iss='https://cognito-idp.us-east-1.amazonaws.com/x')}"},
        {"Authorization": f"Bearer {token(client_id='another-app')}"},
        {"Authorization": f"Bearer {token(token_use='id')}"},
    ],
)
def test_requests_without_a_valid_access_token_are_rejected(headers):
    for response in (
        client.get("/api/meetings", headers=headers),
        client.post("/api/meetings", headers=headers, json={}),
    ):
        assert response.status_code == 401
        assert response.headers["www-authenticate"] == "Bearer"


@pytest.mark.usefixtures("protected")
def test_health_stays_public_for_the_load_balancer():
    assert client.get("/health").status_code == 200
