import asyncio
import json
import logging
import time
from datetime import datetime, timezone
from pathlib import Path

import feedparser

from config.settings import DATABASE_FILE
from db.reader import invalidate_db_cache

logger = logging.getLogger(__name__)

# Trusted Pakistani + international news sources
# lang: "en" = English, "ur" = Urdu
RSS_FEEDS = [
    # ── English — Pakistani ───────────────────────────────────────────────────
    {"url": "https://www.dawn.com/feeds/home",                   "source": "Dawn",              "domain": "dawn.com",              "lang": "en"},
    {"url": "https://arynews.tv/feed/",                          "source": "ARY News",          "domain": "arynews.tv",            "lang": "en"},
    {"url": "https://www.geo.tv/rss/",                           "source": "Geo News",          "domain": "geo.tv",                "lang": "en"},
    {"url": "https://www.thenews.com.pk/rss/1/8",                "source": "The News",          "domain": "thenews.com.pk",        "lang": "en"},
    {"url": "https://tribune.com.pk/feed",                       "source": "Express Tribune",   "domain": "tribune.com.pk",        "lang": "en"},
    {"url": "https://www.pakistantoday.com.pk/feed/",            "source": "Pakistan Today",    "domain": "pakistantoday.com.pk",  "lang": "en"},
    {"url": "https://dailytimes.com.pk/feed/",                   "source": "Daily Times",       "domain": "dailytimes.com.pk",     "lang": "en"},
    {"url": "https://nation.com.pk/feed/",                       "source": "The Nation",        "domain": "nation.com.pk",         "lang": "en"},
    {"url": "https://www.brecorder.com/feed",                    "source": "Business Recorder", "domain": "brecorder.com",         "lang": "en"},
    {"url": "https://dunyanews.tv/index.php/en?format=feed",     "source": "Dunya News",        "domain": "dunyanews.tv",          "lang": "en"},
    {"url": "https://www.samaa.tv/feed/",                        "source": "Samaa TV",          "domain": "samaa.tv",              "lang": "en"},
    # ── English — International ───────────────────────────────────────────────
    {"url": "https://feeds.bbci.co.uk/news/world/rss.xml",       "source": "BBC News",          "domain": "bbc.com",               "lang": "en"},
    {"url": "https://feeds.bbci.co.uk/news/south_asia/rss.xml",  "source": "BBC South Asia",    "domain": "bbc.com",               "lang": "en"},
    {"url": "https://feeds.reuters.com/reuters/topNews",         "source": "Reuters",           "domain": "reuters.com",           "lang": "en"},
    {"url": "https://www.aljazeera.com/xml/rss/all.xml",         "source": "Al Jazeera",        "domain": "aljazeera.com",         "lang": "en"},
    {"url": "https://feeds.apnews.com/apnews/topnews",           "source": "AP News",           "domain": "apnews.com",            "lang": "en"},
    {"url": "https://rss.cnn.com/rss/edition.rss",               "source": "CNN",               "domain": "cnn.com",               "lang": "en"},
    {"url": "https://feeds.skynews.com/feeds/rss/world.xml",     "source": "Sky News",          "domain": "skynews.com",           "lang": "en"},
    # ── Urdu ─────────────────────────────────────────────────────────────────
    {"url": "https://feeds.bbci.co.uk/urdu/rss.xml",             "source": "BBC Urdu",          "domain": "bbc.com/urdu",          "lang": "ur"},
    {"url": "https://www.express.pk/feed/",                      "source": "Express News",      "domain": "express.pk",            "lang": "ur"},
    {"url": "https://jang.com.pk/rss/",                          "source": "Jang",              "domain": "jang.com.pk",           "lang": "ur"},
    {"url": "https://urdu.geo.tv/rss/",                          "source": "Geo Urdu",          "domain": "urdu.geo.tv",           "lang": "ur"},
    {"url": "https://urdu.arynews.tv/feed/",                     "source": "ARY Urdu",          "domain": "urdu.arynews.tv",       "lang": "ur"},
    {"url": "https://www.nawaiwaqt.com.pk/feed/",                "source": "Nawaiwaqt",         "domain": "nawaiwaqt.com.pk",      "lang": "ur"},
    {"url": "https://www.urdupoint.com/news/feed/",              "source": "Urdupoint",         "domain": "urdupoint.com",         "lang": "ur"},
    {"url": "https://www.independenturdu.com/feed",              "source": "Independent Urdu",  "domain": "independenturdu.com",   "lang": "ur"},
]

MAX_DB_SIZE = 120_000  # cap total articles to avoid unbounded growth
_PER_FEED_LIMIT = 50   # articles to take from each feed per refresh


def _parse_date(entry) -> str:
    """Return ISO-8601 UTC string from a feedparser entry, or now()."""
    try:
        if hasattr(entry, "published_parsed") and entry.published_parsed:
            ts = time.mktime(entry.published_parsed)
            return datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()
    except Exception:
        pass
    return datetime.now(timezone.utc).isoformat()


def _fetch_one_feed(feed_meta: dict) -> list[dict]:
    """Synchronous RSS fetch — runs in a thread via asyncio.to_thread."""
    try:
        parsed = feedparser.parse(feed_meta["url"])
        articles = []
        for entry in parsed.entries[:_PER_FEED_LIMIT]:
            title   = (entry.get("title")   or "").strip()
            summary = (entry.get("summary") or entry.get("description") or "").strip()
            url     = (entry.get("link")    or "").strip()

            if not title or not url:
                continue

            articles.append({
                "title":       title,
                "summary":     summary,
                "body":        summary,
                "source":      feed_meta["source"],
                "domain":      feed_meta["domain"],
                "url":         url,
                "publishedAt": _parse_date(entry),
                "language":    feed_meta["lang"],
            })
        return articles
    except Exception as exc:
        logger.warning("Feed fetch failed [%s]: %s", feed_meta["source"], exc)
        return []


async def refresh_news_db() -> int:
    """
    Fetch all RSS feeds concurrently, deduplicate by URL, and append new
    articles to global_news_db.json. Returns the number of articles added.
    """
    db_path = Path(DATABASE_FILE)

    try:
        existing: list = json.loads(db_path.read_text(encoding="utf-8")) if db_path.exists() else []
    except Exception:
        existing = []

    existing_urls: set = {art.get("url", "") for art in existing if art.get("url")}

    # Fetch all feeds concurrently
    tasks = [asyncio.to_thread(_fetch_one_feed, feed) for feed in RSS_FEEDS]
    results = await asyncio.gather(*tasks, return_exceptions=True)

    new_articles: list = []
    for result in results:
        if isinstance(result, Exception):
            continue
        for art in result:
            if art["url"] and art["url"] not in existing_urls:
                new_articles.append(art)
                existing_urls.add(art["url"])

    if not new_articles:
        logger.info("News refresh: no new articles found.")
        return 0

    combined = existing + new_articles
    if len(combined) > MAX_DB_SIZE:
        combined = combined[-MAX_DB_SIZE:]

    db_path.write_text(json.dumps(combined, ensure_ascii=False), encoding="utf-8")
    invalidate_db_cache()
    logger.info("News refresh: +%d articles (total: %d).", len(new_articles), len(combined))
    return len(new_articles)


async def news_refresh_loop() -> None:
    """Background asyncio task: refresh news immediately, then every 30 minutes."""
    while True:
        try:
            await refresh_news_db()
        except Exception as exc:
            logger.error("News refresh loop error: %s", exc)
        await asyncio.sleep(1800)  # 30 minutes
