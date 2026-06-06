import os

from fastapi import APIRouter, Depends, HTTPException
from db.reader import safe_read_db
from middleware.auth import require_firebase_auth

router = APIRouter()

@router.get("/debug-db")
def debug_db(user: dict = Depends(require_firebase_auth)):
    if os.getenv("DEBUG", "").lower() not in ("1", "true", "yes"):
        raise HTTPException(status_code=404, detail="Not found")

    db = safe_read_db()
    counts: dict = {}
    for it in db:
        src = (it.get("source") or it.get("sourceName") or "Unknown").strip()
        counts[src] = counts.get(src, 0) + 1

    return {
        "count": len(db),
        "by_source": counts,
        "sample": db[:3],
    }
