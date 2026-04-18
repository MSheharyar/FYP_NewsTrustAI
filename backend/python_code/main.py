from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError

from routes.verify import router as verify_router
from routes.links import router as links_router
from routes.trending import router as trending_router
from routes.debug import router as debug_router

app = FastAPI(title="NewsTrustAI Backend", version="3.0")

@app.on_event("startup")
def _startup_warmup():
    """
    Load heavy ML resources once (if available) so requests don't pay the cost.
    Falls back gracefully when torch/transformers or model files aren't present.
    """
    try:
        from services.bert import warmup_bert
        warmup_bert()
    except Exception:
        # Keep backend usable even if warmup fails.
        pass

@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    detail = exc.detail
    message = detail if isinstance(detail, str) else "Request failed"
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": True, "message": message, "detail": detail},
    )

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    # FastAPI returns a list of errors; surface the first message for UX.
    errors = exc.errors() if hasattr(exc, "errors") else []
    msg = "Invalid request"
    if errors and isinstance(errors, list):
        first = errors[0] or {}
        m = first.get("msg")
        if isinstance(m, str) and m.strip():
            msg = m.strip()
    return JSONResponse(
        status_code=422,
        content={"error": True, "message": msg, "detail": errors},
    )

@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    # Avoid leaking stack traces to clients; keep message stable for Flutter UI.
    return JSONResponse(
        status_code=500,
        content={"error": True, "message": "Internal server error"},
    )

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(verify_router)
app.include_router(links_router)
app.include_router(trending_router)
app.include_router(debug_router)