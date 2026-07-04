from fastapi import APIRouter, Request
from db.reader import safe_read_db
from routes.verify import limiter

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

    # Freshest articles first
    items.sort(key=lambda x: x.get("publishedAt") or "", reverse=True)

    buckets = {}
    for it in items:
        src = (it.get("source") or it.get("sourceName") or "Unknown").strip()
        buckets.setdefault(src, []).append(it)

    wanted = 10
    out = []
    sources = sorted(buckets.keys())

    i = 0
    while len(out) < wanted and sources:
        src = sources[i % len(sources)]
        if buckets[src]:
            out.append(buckets[src].pop(0))
        else:
            sources.remove(src)
            if not sources:
                break
        i += 1

    return {"items": out}
