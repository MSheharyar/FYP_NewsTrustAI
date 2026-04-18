from fastapi import APIRouter, Body, HTTPException
from typing import Tuple
import requests
from bs4 import BeautifulSoup

from services.verification import hybrid_decision
from utils.net import get_domain, domain_in_set
from config.settings import MAIN_SOURCE_DOMAINS

router = APIRouter()

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
    response = session.get(url, headers=headers, timeout=20)
    response.raise_for_status()

    soup = BeautifulSoup(response.text, "html.parser")

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
            text = " ".join(c.get_text(" ", strip=True).split())
            if len(text) > 200:
                title = soup.title.string if soup.title else ""
                return title or "", text

    text = " ".join(soup.get_text(" ", strip=True).split())
    title = soup.title.string if soup.title else ""
    return title or "", text


@router.post("/verify-link")
def verify_link(payload: dict = Body(...)):
    return analyze_link(payload)


@router.post("/analyze-link")
def analyze_link(payload: dict = Body(...)):
    url = (payload.get("url") or "").strip()

    if not url:
        raise HTTPException(status_code=400, detail="URL is empty.")

    if not (url.startswith("http://") or url.startswith("https://")):
        raise HTTPException(status_code=400, detail="Invalid URL.")

    domain = get_domain(url)
    is_main_source = domain_in_set(domain, MAIN_SOURCE_DOMAINS)

    title = ""
    extracted_text = ""
    extraction_error = None

    try:
        title, text = fetch_article_text(url)
        extracted_text = ((title or "") + "\n\n" + (text or "")).strip()
        if len(extracted_text) < 80:
            extraction_error = "Could not extract enough article text."
    except Exception as e:
        extraction_error = str(e)

    # If invalid path => 404 => do NOT verify
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

    # If extraction fails (403/anti-bot), run fallback
    if extraction_error and not extracted_text:
        fallback_text = (title or "").strip() or url
        result = hybrid_decision(fallback_text, source_domain=domain)
        result.update({
            "link_url": url,
            "link_title": title or "",
            "link_domain": domain,
            "source_tier": "main" if is_main_source else "other",
            "extraction_error": extraction_error,
            "note": "Site blocked full-text extraction (403/anti-bot). Used fallback verification.",
        })
        if ("final_confidence" not in result) and (result.get("confidence") is not None):
            result["final_confidence"] = result["confidence"]
        return result

    # Normal case: verify extracted content
    result = hybrid_decision(extracted_text, source_domain=domain)
    result.update({
        "link_url": url,
        "link_title": title or "",
        "link_domain": domain,
        "source_tier": "main" if is_main_source else "other",
        "extraction_error": extraction_error,
    })
    if ("final_confidence" not in result) and (result.get("confidence") is not None):
        result["final_confidence"] = result["confidence"]
    return result
