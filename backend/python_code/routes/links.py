import ipaddress
import logging
import socket
from typing import Tuple
from urllib.parse import urlparse

import requests
from bs4 import BeautifulSoup
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, HttpUrl

from routes.verify import run_full_pipeline, limiter
from utils.net import get_domain, domain_in_set
from config.settings import MAIN_SOURCE_DOMAINS, LINK_FETCH_TIMEOUT
from middleware.auth import require_firebase_auth

logger = logging.getLogger(__name__)
router = APIRouter()


class AnalyzeLinkRequest(BaseModel):
    url: HttpUrl


def _is_safe_url(url: str) -> bool:
    """Reject URLs that resolve to private/loopback/internal IPs (SSRF prevention)."""
    try:
        hostname = urlparse(url).hostname
        if not hostname:
            return False
        ip = socket.gethostbyname(hostname)
        addr = ipaddress.ip_address(ip)
        if addr.is_private or addr.is_loopback or addr.is_link_local or addr.is_multicast or addr.is_reserved:
            return False
        return True
    except Exception:
        return False


def fetch_article_text(url: str) -> Tuple[str, str]:
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/120.0 Safari/537.36"
        ),
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
        "Cache-Control": "no-cache",
        "Pragma": "no-cache",
        "Upgrade-Insecure-Requests": "1",
    }

    session = requests.Session()
    response = session.get(url, headers=headers, timeout=LINK_FETCH_TIMEOUT)
    response.raise_for_status()

    soup = BeautifulSoup(response.text, "html.parser")

    for tag in soup(["script", "style", "noscript", "iframe", "nav", "header", "footer", "aside"]):
        tag.decompose()

    title = (soup.title.string or "").strip() if soup.title else ""

    # BBC publishes article body as multiple data-component="text-block" divs
    bbc_blocks = soup.find_all("div", attrs={"data-component": "text-block"})
    if bbc_blocks:
        text = " ".join(b.get_text(" ", strip=True) for b in bbc_blocks)
        if len(text) > 200:
            return title, text

    # Ordered selectors: site-specific first, then generic semantic/structural
    selectors = [
        ("article", {}),
        ("div", {"class": "article__content"}),        # CNN
        ("div", {"class": "article-body"}),             # Reuters, AP
        ("div", {"class": "story-content"}),            # Dawn
        ("div", {"class": "story__content"}),           # ARY News
        ("div", {"class": "story__body"}),              # ARY News
        ("div", {"class": "wysiwyg--all-content"}),     # Al Jazeera
        ("div", {"class": "article__body"}),            # BBC fallback
        ("div", {"class": "post__content"}),            # Guardian variants
        ("div", {"class": "entry-content"}),            # WordPress generic
        ("div", {"class": "post-content"}),             # WordPress generic
        ("div", {"class": "td-post-content"}),          # WordPress TDPaper theme
        ("div", {"class": "main-content"}),
        ("div", {"class": "content"}),
        ("div", {"id": "article-body"}),
        ("div", {"id": "content"}),
        ("main", {}),
    ]

    for tag, attrs in selectors:
        el = soup.find(tag, attrs) if attrs else soup.find(tag)
        if el:
            text = " ".join(el.get_text(" ", strip=True).split())
            if len(text) > 200:
                return title, text

    # Paragraph fallback: join substantial <p> tags (skips nav/footer noise)
    paras = soup.find_all("p")
    if paras:
        text = " ".join(
            p.get_text(" ", strip=True)
            for p in paras
            if len(p.get_text(strip=True)) > 40
        )
        if len(text) > 200:
            return title, text

    # Last resort: raw page text
    text = " ".join(soup.get_text(" ", strip=True).split())
    return title, text


def _attach_link_meta(
    result: dict,
    url: str,
    title: str,
    domain: str,
    is_main_source: bool,
    extraction_error,
    note: str = "",
) -> None:
    result["link_url"]   = url
    result["link_title"] = title or ""
    result["link_domain"] = domain
    result["extraction_error"] = extraction_error
    if note:
        result["note"] = note
    # Only set source_tier from the URL domain when hybrid couldn't determine
    # it from evidence — avoids overwriting a meaningful hybrid verdict.
    if result.get("source_tier", "unknown") == "unknown":
        result["source_tier"] = "main" if is_main_source else "other"
    if "final_confidence" not in result and result.get("confidence") is not None:
        result["final_confidence"] = result["confidence"]


def _core(payload: AnalyzeLinkRequest) -> dict:
    url    = str(payload.url).strip()

    if not _is_safe_url(url):
        raise HTTPException(status_code=400, detail="URL is not allowed.")

    domain = get_domain(url)
    is_main_source = domain_in_set(domain, MAIN_SOURCE_DOMAINS)

    title            = ""
    extracted_text   = ""
    extraction_error = None

    try:
        title, text  = fetch_article_text(url)
        extracted_text = ((title or "") + "\n\n" + (text or "")).strip()
        if len(extracted_text) < 80:
            extraction_error = "Could not extract enough article text."
    except requests.exceptions.Timeout:
        extraction_error = "Timed out while fetching the article."
    except requests.exceptions.ConnectionError:
        extraction_error = "Failed to connect to the article host."
    except requests.exceptions.HTTPError as e:
        status_code = e.response.status_code if e.response is not None else "unknown"
        extraction_error = f"HTTP {status_code} from article host."
        logger.debug("HTTP error fetching %s: %s", url, e)
    except Exception as e:
        extraction_error = "Failed to process the article."
        logger.debug("Unexpected error fetching %s: %s", url, e)

    # 404 — invalid link, skip verification entirely
    if extraction_error and ("404" in extraction_error or "Not Found" in extraction_error):
        return {
            "error": False,
            "final_label": "unverified",
            "final_confidence": None,
            "authenticity": "unverified",
            "confidence": None,
            "verdict_state": "not_verified",
            "verification_method": "invalid_link",
            "final_reason": "The link appears invalid (page not found / 404).",
            "link_url": url,
            "link_title": title or "",
            "link_domain": domain,
            "source_tier": "main" if is_main_source else "other",
            "extraction_error": extraction_error,
        }

    # 403 / anti-bot — fall back to verifying just the title
    if extraction_error and not extracted_text:
        fallback = (title or "").strip() or url
        result   = run_full_pipeline(fallback)
        _attach_link_meta(
            result, url, title, domain, is_main_source, extraction_error,
            note="Site blocked full-text extraction. Verified using title only.",
        )
        return result

    # Normal path — run the full pipeline on the extracted article text
    result = run_full_pipeline(extracted_text)
    _attach_link_meta(result, url, title, domain, is_main_source, extraction_error)
    return result


@router.post("/analyze-link")
@limiter.limit("10/minute")
def analyze_link(request: Request, payload: AnalyzeLinkRequest, user: dict = Depends(require_firebase_auth)):
    result = _core(payload)
    if isinstance(result, dict) and result.get("error") is True:
        raise HTTPException(status_code=400, detail=str(result.get("message") or "Unable to verify link"))
    return result


@router.post("/verify-link")
@limiter.limit("10/minute")
def verify_link(request: Request, payload: AnalyzeLinkRequest, user: dict = Depends(require_firebase_auth)):
    return analyze_link(request, payload, user)
