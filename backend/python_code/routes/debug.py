from fastapi import APIRouter
from db.reader import safe_read_db

router = APIRouter()

@router.get("/debug-db")
def debug_db():
    db = safe_read_db()

    counts = {}
    for it in db:
        src = (it.get("source") or it.get("sourceName") or "Unknown").strip()
        counts[src] = counts.get(src, 0) + 1

    return {
        "count": len(db),
        "by_source": counts,
        "sample": db[:3]
    }
