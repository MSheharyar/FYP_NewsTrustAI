from datetime import datetime, timezone, timedelta

from fastapi import APIRouter, Request
from db.reader import safe_read_db
from routes.verify import limiter

_EPOCH = datetime.min.replace(tzinfo=timezone.utc)


def _parse_dt(s: str):
    s = (s or "").strip()
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def _pub_dt(it: dict):
    return _parse_dt(it.get("publishedAt")) or _parse_dt(it.get("scrapedAt"))

def _pick_first(it: dict, keys: list[str]) -> str:
    for k in keys:
        v = it.get(k)
        if v:
            s = str(v).strip()
            if s:
                return s
    return ""

def _normalize_url(u: str) -> str:
    u = (u or "").strip()
    if not u:
        return ""
    if u.startswith("//"):
        return "https:" + u
    if u.startswith("www."):
        return "https://" + u
    if not (u.startswith("http://") or u.startswith("https://")) and "." in u.split("/")[0]:
        return "https://" + u
    return u

def normalize_item(it: dict) -> dict:
    title = _pick_first(it, ["title", "headline", "name"])
    summary = _pick_first(it, ["summary", "description", "desc", "content"])
    source = _pick_first(it, ["source", "sourceName", "publisher"]) or "News"

    url = _normalize_url(_pick_first(it, ["url", "link", "newsUrl", "articleUrl"]))
    image = _normalize_url(_pick_first(it, ["imageUrl", "urlToImage", "image", "image_url", "thumbnail"]))

    out = dict(it)
    out["title"] = title or out.get("title") or "No Title"
    out["summary"] = summary or out.get("summary") or "No summary available"
    out["source"] = source
    out["url"] = url
    out["imageUrl"] = image
    return out

router = APIRouter()

@router.get("/trending")
@limiter.limit("30/minute")
def trending(request: Request):
    items = safe_read_db()
    if not items:
        return {"items": []}

    items = [normalize_item(it) for it in items if isinstance(it, dict)]

    # Freshest first (undated articles sink to the bottom).
    items.sort(key=lambda x: _pub_dt(x) or _EPOCH, reverse=True)

    # Prefer articles from the last few days so stale/renamed dead feeds don't
    # dominate the list; fall back to the freshest overall if too few recent ones.
    cutoff = datetime.now(timezone.utc) - timedelta(days=3)
    recent = [it for it in items if (_pub_dt(it) or _EPOCH) >= cutoff]
    pool = recent if len(recent) >= 10 else items

    # Bucket by source, then order sources by their freshest article so active
    # feeds lead. Round-robin one-per-source for a fresh AND diverse top list.
    buckets: dict[str, list] = {}
    for it in pool:
        src = (it.get("source") or it.get("sourceName") or "Unknown").strip()
        buckets.setdefault(src, []).append(it)

    sources = sorted(
        buckets.keys(),
        key=lambda s: _pub_dt(buckets[s][0]) or _EPOCH,
        reverse=True,
    )

    wanted = 10
    out = []
    while len(out) < wanted and sources:
        for src in list(sources):
            if len(out) >= wanted:
                break
            if buckets[src]:
                out.append(buckets[src].pop(0))
            if not buckets[src]:
                sources.remove(src)

    return {"items": out}
