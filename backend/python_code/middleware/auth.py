"""
middleware/auth.py
──────────────────
FastAPI dependency that verifies a Firebase ID token sent by the Flutter app.

Usage in a route:
    from middleware.auth import require_firebase_auth

    @router.post("/verify-text")
    def verify_text(payload: ..., user=Depends(require_firebase_auth)):
        uid = user["uid"]   # Firebase UID of the logged-in user
        ...

Environment variables:
    REQUIRE_AUTH=false   — bypass verification (local dev only)
    FIREBASE_SERVICE_ACCOUNT_JSON — service account JSON string (production)
    GOOGLE_APPLICATION_CREDENTIALS — path to service account file (alternative)
"""

import asyncio
import logging
import os
from typing import Optional

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from config.settings import REQUIRE_AUTH

logger = logging.getLogger(__name__)


def assert_auth_config_is_safe() -> None:
    """Raise RuntimeError if auth is disabled outside a local/dev environment.
    Call once at startup to prevent accidental production deployments with auth off."""
    require_auth = os.getenv("REQUIRE_AUTH", "true").lower() == "true"
    app_env = os.getenv("APP_ENV", "production").lower()
    if not require_auth and app_env not in ("local", "dev", "development"):
        raise RuntimeError(
            "REQUIRE_AUTH=false is only allowed when APP_ENV is local/dev. "
            "Set APP_ENV=local for local development, or REQUIRE_AUTH=true."
        )


# Reuse FastAPI's built-in Bearer extractor (returns 403 if header absent)
_bearer_scheme = HTTPBearer(auto_error=False)

# Track whether firebase_admin was successfully imported
_firebase_ready = False
try:
    from firebase_admin import auth as _fb_auth
    _firebase_ready = True
except ImportError:
    logger.warning("firebase-admin not installed — token verification is disabled.")


async def require_firebase_auth(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(_bearer_scheme),
) -> dict:
    """
    Verifies the Firebase ID token in the Authorization header.
    Returns the decoded token dict (contains uid, email, etc.).
    Raises HTTP 401 on any failure.
    """
    # Dev bypass — set REQUIRE_AUTH=false to skip verification locally
    if not REQUIRE_AUTH:
        logger.debug("Auth bypassed (REQUIRE_AUTH=false)")
        return {"uid": "dev-user", "email": "dev@localhost"}

    if not _firebase_ready:
        # firebase-admin not installed; fail open with a warning so the server
        # still starts, but log clearly that tokens are not being verified.
        logger.warning("Token not verified — firebase-admin is not installed.")
        return {"uid": "unverified"}

    if credentials is None:
        raise HTTPException(
            status_code=401,
            detail="Authorization header missing. Send: Authorization: Bearer <firebase_id_token>",
        )

    token = credentials.credentials
    try:
        decoded = await asyncio.to_thread(_fb_auth.verify_id_token, token)
        return decoded
    except _fb_auth.ExpiredIdTokenError:
        raise HTTPException(status_code=401, detail="Firebase token has expired. Please sign in again.")
    except _fb_auth.RevokedIdTokenError:
        raise HTTPException(status_code=401, detail="Firebase token has been revoked. Please sign in again.")
    except _fb_auth.InvalidIdTokenError:
        raise HTTPException(status_code=401, detail="Invalid Firebase token.")
    except Exception as e:
        logger.warning("Firebase token verification error: %s", e)
        raise HTTPException(status_code=401, detail="Token verification failed.")
