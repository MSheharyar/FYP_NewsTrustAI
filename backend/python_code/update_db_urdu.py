import os
import json
import time
import requests
from datetime import datetime, timezone, timedelta
from typing import List, Dict, Any, Optional
from bs4 import BeautifulSoup
from urllib.parse import urlparse
import xml.etree.ElementTree as ET

from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATABASE_FILE = os.getenv("DATABASE_FILE", os.path.join(BASE_DIR, "global_news_db.json"))

DAYS_BACK = int(os.getenv("DB_DAYS_BACK", "7"))
MAX_PER_FEED = int(os.getenv("DB_MAX_PER_FEED", "80"))
FETCH_BODY = os.getenv("DB_FETCH_BODY", "1").strip() == "1"
BODY_MAX_CHARS = int(os.getenv("DB_BODY_MAX_CHARS", "2000"))

KEEP_ALL = os.getenv("DB_KEEP_ALL", "1").strip() == "1"
TRIM_DAYS = int(os.getenv("DB_TRIM_DAYS", str(DAYS_BACK)))

URDU_MAIN_FEEDS = {
    "GEO_URDU": ["https://urdu.geo.tv/rss"],
    "ARY_URDU": ["https://urdu.arynews.tv/feed/"],
    "BBC_URDU": ["https://feeds.bbci.co.uk/urdu/rss.xml"],
    "EXPRESS_NEWS": ["https://www.express.pk/feed/"],
    "INDEPENDENT_URDU": ["https://www.independenturdu.com/rss.xml"]
}

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "ur-PK,ur;q=0.9,en-US;q=0.8,en;q=0.7",
    "Connection": "close",
}

def _make_session() -> requests.Session:
    s = requests.Session()
    retry = Retry(
        total=4, connect=4, read=4, backoff_factor=0.8,
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=("GET",), raise_on_status=False,
        respect_retry_after_header=True,
    )
    adapter = HTTPAdapter(max_retries=retry, pool_connections=20, pool_maxsize=20)
    s.mount("http://", adapter)
    s.mount("https://", adapter)
    return s

_SESSION = _make_session()

def get_domain(url: str) -> str:
    host = urlparse(url).netloc.lower()
    return host.replace("www.", "")

def now_utc() -> datetime:
    return datetime.now(timezone.utc)

def parse_rfc822_or_iso(dt_str: str) -> Optional[datetime]:
    if not dt_str:
        return None
    s = dt_str.strip()
    try:
        from email.utils import parsedate_to_datetime
        dt = parsedate_to_datetime(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    except Exception:
        pass
    try:
        if s.endswith("Z"):
            s = s.replace("Z", "+00:00")
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    except Exception:
        return None

def safe_read_db() -> List[Dict[str, Any]]:
    if not os.path.exists(DATABASE_FILE):
        return []
    try:
        with open(DATABASE_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except Exception:
        return []

def safe_write_db(items: List[Dict[str, Any]]) -> None:
    tmp = DATABASE_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=2)
    os.replace(tmp, DATABASE_FILE)

def fetch_xml(url: str, timeout: int = 25) -> Optional[str]:
    for attempt in range(1, 4):
        try:
            r = _SESSION.get(url, headers=HEADERS, timeout=timeout, allow_redirects=True)
            if r.status_code == 200 and r.text:
                return r.text
            if r.status_code == 403:
                alt_headers = dict(HEADERS)
                alt_headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/122 Safari/537.36"
                r2 = _SESSION.get(url, headers=alt_headers, timeout=timeout, allow_redirects=True)
                if r2.status_code == 200 and r2.text:
                    return r2.text
            print(f"Feed fetch failed {r.status_code}: {url}")
            return None
        except requests.exceptions.SSLError as e:
            time.sleep(1.2 * attempt)
            continue
        except requests.exceptions.RequestException as e:
            time.sleep(1.0 * attempt)
            continue
        except Exception as e:
            return None
    return None

def normalize_ws(s: str) -> str:
    return " ".join((s or "").split())

def strip_html(html: str) -> str:
    if not html:
        return ""
    soup = BeautifulSoup(html, "html.parser")
    for tag in soup(["script", "style", "noscript", "iframe"]):
        tag.decompose()
    return normalize_ws(soup.get_text(" ", strip=True))

def fetch_article_text(url: str) -> str:
    try:
        r = _SESSION.get(url, headers=HEADERS, timeout=25, allow_redirects=True)
        if r.status_code != 200:
            return ""
        soup = BeautifulSoup(r.text, "html.parser")
        for tag in soup(["script", "style", "noscript", "iframe"]):
            tag.decompose()
        candidates = [
            soup.find("article"),
            soup.find("div", class_="story__content"),
            soup.find("div", class_="story__body"),
            soup.find("div", class_="content"),
            soup.find("div", class_="main-content"),
        ]
        for c in candidates:
            if c:
                t = normalize_ws(c.get_text(" ", strip=True))
                if len(t) > 200:
                    return t[:BODY_MAX_CHARS]
        t = normalize_ws(soup.get_text(" ", strip=True))
        return t[:BODY_MAX_CHARS]
    except Exception:
        return ""

def _et_text(el: Optional[ET.Element]) -> str:
    if el is None:
        return ""
    return normalize_ws(el.text or "")

def parse_feed_items(xml_text: str) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    try:
        root = ET.fromstring(xml_text)
    except Exception:
        return out

    channel = root.find("channel")
    if channel is not None:
        for item in channel.findall(".//item"):
            title = item.findtext("title") or ""
            link = item.findtext("link") or ""
            pub = item.findtext("pubDate") or item.findtext("{http://purl.org/dc/elements/1.1/}date") or ""
            desc = item.findtext("description") or ""
            out.append({
                "title": normalize_ws(title),
                "url": normalize_ws(link),
                "publishedAt": pub.strip(),
                "summary": strip_html(desc)[:400] if desc else "",
            })
        if out:
            return out

    ns_atom = "{http://www.w3.org/2005/Atom}"
    entries = root.findall(f".//{ns_atom}entry")
    if not entries:
        entries = root.findall(".//entry")

    for e in entries:
        title = e.findtext(f"{ns_atom}title") or e.findtext("title") or ""
        published = (
            e.findtext(f"{ns_atom}published") or e.findtext("published")
            or e.findtext(f"{ns_atom}updated") or e.findtext("updated") or ""
        )
        link = ""
        link_el = e.find(f"{ns_atom}link") or e.find("link")
        if link_el is not None:
            href = link_el.attrib.get("href")
            if href:
                link = href
            else:
                link = _et_text(link_el)

        summary = e.findtext(f"{ns_atom}summary") or e.findtext("summary") or ""
        content = e.findtext(f"{ns_atom}content") or e.findtext("content") or ""
        desc = summary or content

        out.append({
            "title": normalize_ws(title),
            "url": normalize_ws(link),
            "publishedAt": published.strip(),
            "summary": strip_html(desc)[:400] if desc else "",
        })

    return out

def keep_last_days(items: List[Dict[str, Any]], days_back: int) -> List[Dict[str, Any]]:
    cutoff = now_utc() - timedelta(days=days_back)
    kept = []
    for it in items:
        dt = parse_rfc822_or_iso(it.get("publishedAt") or "")
        if dt is None:
            kept.append(it)
            continue
        if dt >= cutoff:
            kept.append(it)
    return kept

def dedupe_by_url(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    seen = set()
    out = []
    for it in items:
        u = (it.get("url") or "").strip()
        if not u:
            continue
        if u in seen:
            continue
        seen.add(u)
        out.append(it)
    return out

def merge_into_db(existing: List[Dict[str, Any]], incoming: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    by_url = {}
    for it in existing:
        u = (it.get("url") or "").strip()
        if u:
            by_url[u] = it

    for it in incoming:
        u = (it.get("url") or "").strip()
        if not u:
            continue
        prev = by_url.get(u, {})
        merged = {**prev, **it}
        by_url[u] = merged

    merged_list = list(by_url.values())

    def sort_dt(x):
        dt = parse_rfc822_or_iso(x.get("publishedAt") or "") or parse_rfc822_or_iso(x.get("scrapedAt") or "")
        return dt or datetime(1970, 1, 1, tzinfo=timezone.utc)

    merged_list.sort(key=sort_dt, reverse=True)
    return merged_list

def update():
    existing = safe_read_db()

    all_new = []
    scraped_at = now_utc().isoformat()

    for source_name, feeds in URDU_MAIN_FEEDS.items():
        for feed_url in feeds:
            xml_text = fetch_xml(feed_url)
            if not xml_text:
                continue

            items = parse_feed_items(xml_text)
            if not items:
                print(f"0 items parsed for {source_name}: {feed_url}")
                continue

            items = items[:MAX_PER_FEED]
            items = keep_last_days(items, DAYS_BACK)

            enriched = []
            for it in items:
                url = (it.get("url") or "").strip()
                if not url:
                    continue

                pub_dt = parse_rfc822_or_iso(it.get("publishedAt") or "")
                pub_iso = pub_dt.isoformat() if pub_dt else None

                entry = {
                    "title": it.get("title") or "",
                    "url": url,
                    "source": source_name,
                    "sourceName": source_name,
                    "publishedAt": pub_iso,
                    "scrapedAt": scraped_at,
                    "summary": it.get("summary") or "",
                    "domain": get_domain(url),
                    "language": "ur"
                }

                if FETCH_BODY:
                    body = fetch_article_text(url)
                    if body:
                        entry["body"] = body

                enriched.append(entry)

            all_new.extend(enriched)
            print(f"{source_name} +{len(enriched)} items from {feed_url}")

    all_new = dedupe_by_url(all_new)
    merged = merge_into_db(existing, all_new)

    if KEEP_ALL:
        safe_write_db(merged)
        print(f"Urdu DB Updated (archive): total {len(merged)} items saved to {DATABASE_FILE}")
        return

    cutoff = now_utc() - timedelta(days=TRIM_DAYS)
    trimmed = []
    for it in merged:
        dt = parse_rfc822_or_iso(it.get("publishedAt") or "") or parse_rfc822_or_iso(it.get("scrapedAt") or "")
        if dt is None or dt >= cutoff:
            trimmed.append(it)

    safe_write_db(trimmed)
    print(f"Urdu DB Updated: {len(trimmed)} items saved to {DATABASE_FILE}")

if __name__ == "__main__":
    update()
