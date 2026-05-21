import json
import logging
import os
import re
import threading
from config.settings import DATABASE_FILE, BM25_TOP_K

logger = logging.getLogger(__name__)

_db_cache = None
_keyword_index: dict | None = None
_bm25_index = None    # BM25Okapi instance, or False if unavailable
_bm25_tried = False   # whether we've attempted to build the BM25 index
_db_mtime: float | None = None   # mtime of the DB file when last loaded
_db_lock = threading.Lock()

def invalidate_db_cache() -> None:
    """Drop all cached DB state so the next read reloads from disk."""
    global _db_cache, _keyword_index, _bm25_index, _bm25_tried, _db_mtime
    with _db_lock:
        _db_cache = None
        _keyword_index = None
        _bm25_index = None
        _bm25_tried = False
        _db_mtime = None
    logger.info("DB cache invalidated.")


def safe_read_db() -> list:
    global _db_cache, _db_mtime

    # Fast path: check if the file has been modified since last load.
    if _db_cache is not None:
        try:
            current_mtime = os.path.getmtime(DATABASE_FILE)
            if current_mtime == _db_mtime:
                return _db_cache
            logger.info("DB file changed (mtime %s → %s) — reloading.", _db_mtime, current_mtime)
            invalidate_db_cache()
        except OSError:
            return _db_cache

    with _db_lock:
        if _db_cache is not None:
            return _db_cache

        if not os.path.exists(DATABASE_FILE):
            logger.warning("Database file not found: %s — returning empty DB.", DATABASE_FILE)
            _db_cache = []
            return _db_cache

        try:
            with open(DATABASE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            _db_cache = data if isinstance(data, list) else []
            _db_mtime = os.path.getmtime(DATABASE_FILE)
            logger.info("Loaded %d articles from %s", len(_db_cache), DATABASE_FILE)
        except Exception as e:
            logger.error("Failed to load database from %s: %s — using empty DB.", DATABASE_FILE, e)
            _db_cache = []

        return _db_cache


def _tokenize_bm25(text: str) -> list:
    """Lowercase 3+ char alphanumeric tokens for BM25."""
    return re.findall(r'\b[a-z]{3,}\b', text.lower())


def _build_bm25_index(db: list):
    """Build a BM25Okapi index over title+summary of every article."""
    try:
        from rank_bm25 import BM25Okapi
        corpus = [
            _tokenize_bm25(f"{art.get('title', '')} {art.get('summary', '')}")
            for art in db
        ]
        bm25 = BM25Okapi(corpus)
        logger.info("BM25 index built over %d articles.", len(db))
        return bm25
    except ImportError:
        logger.warning(
            "rank_bm25 not installed — falling back to keyword index. "
            "Install with: pip install rank-bm25"
        )
        return None


def _build_keyword_index(db: list) -> dict:
    idx: dict = {}
    for i, art in enumerate(db):
        blob = f"{art.get('title', '')} {art.get('summary', '')}".lower()
        for word in set(re.findall(r'\b[a-z]{4,}\b', blob)):
            idx.setdefault(word, []).append(i)
    return idx


def get_candidate_articles(keywords: list[str], top_k: int = BM25_TOP_K) -> list:
    """
    Return the most relevant DB articles for the given keyword tokens.

    Uses BM25Okapi ranked retrieval when rank_bm25 is installed (returns the
    top_k highest-scoring articles with score > 0). Falls back to the boolean
    keyword-index approach when the package is unavailable.
    """
    global _keyword_index, _bm25_index, _bm25_tried
    db = safe_read_db()

    if not db:
        return []

    if not keywords:
        return db

    # ── BM25 path ──────────────────────────────────────────────
    if not _bm25_tried:
        with _db_lock:
            if not _bm25_tried:
                _bm25_index = _build_bm25_index(db)
                _bm25_tried = True

    if _bm25_index:
        query_tokens = _tokenize_bm25(" ".join(keywords))
        scores = _bm25_index.get_scores(query_tokens)
        # Sort (index, score) pairs descending; keep top_k with score > 0
        ranked = sorted(enumerate(scores), key=lambda x: x[1], reverse=True)
        return [db[i] for i, s in ranked[:top_k] if s > 0]

    # ── Keyword-index fallback ──────────────────────────────────
    if _keyword_index is None:
        with _db_lock:
            if _keyword_index is None:
                _keyword_index = _build_keyword_index(db)

    indices: set = set()
    for kw in keywords:
        indices.update(_keyword_index.get(kw.lower(), []))

    return [db[i] for i in indices]