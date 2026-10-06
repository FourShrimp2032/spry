"""Cognito access-token verification. Enabled only when COGNITO_USER_POOL_ID is set."""

import os
from functools import lru_cache

import jwt
from fastapi import Header, HTTPException


def unauthorized(detail):
    return HTTPException(401, detail, headers={"WWW-Authenticate": "Bearer"})


@lru_cache
def signing_keys(issuer):
    # PyJWKClient caches the pool's keys, so a request does not download the JWKS again.
    return jwt.PyJWKClient(f"{issuer}/.well-known/jwks.json", lifespan=3600, timeout=5)


def require_user(authorization: str | None = Header(default=None)):
    pool_id = os.getenv("COGNITO_USER_POOL_ID")
    if not pool_id:
        return None
    issuer = (
        f"https://cognito-idp.{os.getenv('COGNITO_REGION', 'us-east-1')}.amazonaws.com/{pool_id}"
    )
    scheme, _, token = (authorization or "").partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise unauthorized("Sign in required")
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
        raise HTTPException(503, "Sign-in keys temporarily unavailable") from error
    except jwt.PyJWTError as error:
        raise unauthorized("Invalid or expired token") from error
    # Cognito access tokens carry client_id instead of aud; ID tokens must not open the API.
    if claims["token_use"] != "access" or claims["client_id"] != os.getenv("COGNITO_CLIENT_ID"):
        raise unauthorized("Invalid or expired token")
    return claims
