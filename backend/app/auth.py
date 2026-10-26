"""Cognito access-token verification, shared by the API and the agenda parser Lambda."""

import os
from functools import lru_cache

import jwt
from fastapi import Header, HTTPException


class AuthError(Exception):
    def __init__(self, status, detail):
        super().__init__(detail)
        self.status = status
        self.detail = detail


@lru_cache
def signing_keys(issuer):
    # PyJWKClient caches the pool's keys, so a request does not download the JWKS again.
    return jwt.PyJWKClient(f"{issuer}/.well-known/jwks.json", lifespan=3600, timeout=5)


def verify_access_token(authorization: str | None) -> dict:
    """Claims of a valid Cognito access token for this app's client, else AuthError."""
    pool_id = os.environ["COGNITO_USER_POOL_ID"]
    issuer = (
        f"https://cognito-idp.{os.getenv('COGNITO_REGION', 'us-east-1')}.amazonaws.com/{pool_id}"
    )
    scheme, _, token = (authorization or "").partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise AuthError(401, "Sign in required")
    try:
        key = signing_keys(issuer).get_signing_key_from_jwt(token).key
        claims = jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            issuer=issuer,
            options={"require": ["exp", "iss", "sub", "client_id", "token_use"]},
        )
    except jwt.PyJWKClientConnectionError as error:
        raise AuthError(503, "Sign-in keys temporarily unavailable") from error
    except jwt.PyJWTError as error:
        raise AuthError(401, "Invalid or expired token") from error
    # Cognito access tokens carry client_id instead of aud; ID tokens must not open the API.
    if claims["token_use"] != "access" or claims["client_id"] != os.getenv("COGNITO_CLIENT_ID"):
        raise AuthError(401, "Invalid or expired token")
    return claims


def require_user(authorization: str | None = Header(default=None)):
    """FastAPI dependency. The API is public unless COGNITO_USER_POOL_ID is set."""
    if not os.getenv("COGNITO_USER_POOL_ID"):
        return None
    try:
        return verify_access_token(authorization)
    except AuthError as error:
        headers = {"WWW-Authenticate": "Bearer"} if error.status == 401 else None
        raise HTTPException(error.status, error.detail, headers=headers) from error
