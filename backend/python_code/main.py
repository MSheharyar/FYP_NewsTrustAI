import json
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from config.settings import (
    LOG_LEVEL, CORS_ORIGINS, HF_API_TOKEN, URDU_MODEL_ID,
    FIREBASE_SERVICE_ACCOUNT_JSON, REQUIRE_AUTH,
)
from routes.verify import router as verify_router, limiter
from routes.links import router as links_router
from routes.trending import router as trending_router
from routes.debug import router as debug_router
from routes.chat import router as chat_router

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


def _init_firebase() -> None:
    """Initialise Firebase Admin SDK for server-side token verification."""
    try:
        import firebase_admin
        from firebase_admin import credentials

        if firebase_admin._apps:
            return  # Already initialised (e.g. during hot-reload)

        if FIREBASE_SERVICE_ACCOUNT_JSON:
            sa_info = json.loads(FIREBASE_SERVICE_ACCOUNT_JSON)
            cred = credentials.Certificate(sa_info)
            firebase_admin.initialize_app(cred)
            logger.info("Firebase Admin SDK initialised from FIREBASE_SERVICE_ACCOUNT_JSON.")
        else:
            firebase_admin.initialize_app(options={"projectId": "newstrust-fall"})
            logger.info("Firebase Admin SDK initialised with project ID: newstrust-fall")
    except Exception as e:
        logger.warning(
            "Firebase Admin SDK init failed — token verification will be skipped: %s", e
        )


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """
    Load heavy ML resources once (if available) so requests don't pay the cost.
    Falls back gracefully when torch/transformers or model files aren't present.
    """
    import asyncio
    from middleware.auth import assert_auth_config_is_safe
    assert_auth_config_is_safe()

    # Firebase must be ready before the first request
    if REQUIRE_AUTH:
        _init_firebase()

    try:
        from services.bert import warmup_bert
        bert_status = warmup_bert()
        if bert_status.get("ok"):
            logger.info("BERT model loaded: %s", bert_status.get("note"))
        else:
            logger.warning("BERT model not loaded: %s", bert_status.get("note"))

        if HF_API_TOKEN:
            logger.info("Urdu model ready: %s (HuggingFace API)", URDU_MODEL_ID)
        else:
            logger.warning("HF_API_TOKEN not set — Urdu detection disabled.")

        from text_verifier import warmup_text_verifier
        warmup_text_verifier()

        from db.reader import get_candidate_articles
        get_candidate_articles(["news"])
        logger.info("BM25 index warmed up.")

        from services.facts import facts_from_text
        facts_from_text("test warmup")
        logger.info("spaCy NER warmed up.")
    except Exception as e:
        logger.warning("Startup warmup failed (non-fatal): %s", e)

    # Start background news refresh loop (every 30 minutes)
    try:
        from services.news_fetcher import news_refresh_loop
        asyncio.create_task(news_refresh_loop())
        logger.info("News refresh background task started.")
    except Exception as e:
        logger.warning("News refresh task failed to start (non-fatal): %s", e)

    yield


app = FastAPI(title="NewsTrustAI Backend", version="3.0", lifespan=lifespan)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    detail = exc.detail
    message = detail if isinstance(detail, str) else "Request failed"
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": True, "message": message},
    )

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    errors = exc.errors() if hasattr(exc, "errors") else []
    msg = "Invalid request"
    if errors and isinstance(errors, list):
        first = errors[0] or {}
        m = first.get("msg")
        if isinstance(m, str) and m.strip():
            msg = m.strip()
    return JSONResponse(
        status_code=422,
        content={"error": True, "message": msg},
    )

@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    logger.error("Unhandled exception on %s %s: %s", request.method, request.url.path, exc)
    return JSONResponse(
        status_code=500,
        content={"error": True, "message": "Internal server error"},
    )

# allow_credentials must be False when allow_origins contains "*"
_credentials = "*" not in CORS_ORIGINS
app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=_credentials,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type", "Authorization"],
)

app.include_router(verify_router)
app.include_router(links_router)
app.include_router(trending_router)
app.include_router(debug_router)
app.include_router(chat_router)


@app.get("/health")
def health():
    return {"status": "ok", "version": app.version}