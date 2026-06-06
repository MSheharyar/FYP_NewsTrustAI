import logging
import re

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from typing import Optional, List

from services.chat_service import chat_with_gemini
from db.reader import get_candidate_articles
from services.matching import score_match
from middleware.auth import require_firebase_auth
from routes.verify import limiter

logger = logging.getLogger(__name__)
router = APIRouter()


def _search_db_for_chat(message: str, top_k: int = 5) -> list[dict]:
    keywords = re.findall(r'\b[a-z]{3,}\b', message.lower())
    if not keywords:
        return []
    candidates = get_candidate_articles(keywords, top_k=80)
    scored = []
    for art in candidates:
        blob = f"{art.get('title', '')} {art.get('summary', '')}".strip()
        s = score_match(message, blob)
        if s > 30:
            scored.append((s, art))
    scored.sort(key=lambda x: x[0], reverse=True)
    return [
        {
            "title":   art.get("title", ""),
            "source":  art.get("source") or art.get("sourceName") or "",
            "url":     art.get("url", ""),
            "snippet": (art.get("summary") or art.get("body") or "")[:400],
            "score":   score,
        }
        for score, art in scored[:top_k]
    ]


class _HistoryTurn(BaseModel):
    role: str          # "user" or "model"
    parts: List[str]


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)
    context: Optional[str] = None
    history: Optional[List[_HistoryTurn]] = []


@router.post("/chat")
@limiter.limit("10/minute")
def chat(request: Request, payload: ChatRequest, user: dict = Depends(require_firebase_auth)):
    message = (payload.message or "").strip()
    if not message:
        raise HTTPException(status_code=400, detail="Message is empty.")

    history = [
        {"role": t.role, "parts": t.parts}
        for t in (payload.history or [])
    ]

    db_articles = _search_db_for_chat(message)

    try:
        reply = chat_with_gemini(
            message=message,
            history=history,
            context=payload.context,
            db_articles=db_articles,
        )
        return {"reply": reply}
    except RuntimeError as e:
        logger.error("Chat service runtime error: %s", e)
        raise HTTPException(
            status_code=503,
            detail="Chat service unavailable. GEMINI_API_KEY may not be configured.",
        )
    except Exception as e:
        logger.error("Unexpected chat error: %s", e)
        raise HTTPException(status_code=500, detail="Failed to generate a response.")
