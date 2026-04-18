import re
from db.reader import safe_read_db
from services.matching import score_match
from services.gdelt import gdelt_lookup_domains, CONF_VERY_LOW
from services.factcheck import google_factcheck  # ✅ NEW
from utils.text import clean_claim_text, normalize_text
from config.settings import (
    VERIFY_THRESHOLD,
    CONF_HIGH,
    CONF_SLIGHTLY_LOW,
    CONF_LOW,
    MAIN_SOURCE_DOMAINS,
)

# -----------------------------
# Tuning (lightweight, no ML)
# -----------------------------
MIN_TEXT_LEN = 35

SOFT_CANDIDATE_TOPK = 30
SOFT_MATCH_MIN = float(max(0.30, VERIFY_THRESHOLD * 0.70))
SOFT_MATCH_STRONG = float(max(0.42, VERIFY_THRESHOLD * 0.85))

REQUIRE_GROUP_MATCHES = 2
MIN_GROUP_RATIO = 0.50
HARD_GROUPS = {"numbers", "dates"}


def _norm_domain(d: str) -> str:
    d = (d or "").strip().lower()
    if d.startswith("www."):
        d = d[4:]
    if d.startswith("m."):
        d = d[2:]
    if d == "edition.cnn.com":
        d = "cnn.com"
    return d


def _is_main_source_domain(d: str) -> bool:
    nd = _norm_domain(d)
    return nd in {_norm_domain(x) for x in MAIN_SOURCE_DOMAINS}


def _looks_unstructured(text: str) -> bool:
    t = (text or "").strip()
    if len(t) < MIN_TEXT_LEN:
        return True

    non_alnum = sum(1 for c in t if not c.isalnum() and c not in " .,:;!?-'\"()")
    if non_alnum > 18:
        return True

    has_caps = bool(re.search(r"\b[A-Z][a-z]{2,}\b", t))
    has_num = bool(re.search(r"\d", t))
    if not has_caps and not has_num and len(t) < 120:
        return True

    return False


def _evidence_blob(art: dict) -> str:
    title = normalize_text(art.get("title", ""))
    summary = normalize_text(art.get("summary", ""))
    body = normalize_text(art.get("body", ""))
    blob = f"{title}. {summary}. {body}".strip()
    return blob[:3000]


# -----------------------------
# Key facts extraction (heuristics)
# -----------------------------
_MONTHS = {
    "jan", "january", "feb", "february", "mar", "march", "apr", "april",
    "may", "jun", "june", "jul", "july", "aug", "august",
    "sep", "sept", "september", "oct", "october", "nov", "november",
    "dec", "december",
}

_DAYS = {"monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"}

_ORG_TERMS = {
    "pti", "pmln", "pml-n", "ppp", "mqm", "anp", "jui", "tjp",
    "army", "pakistan army", "isi", "police", "nab", "fbr",
    "supreme court", "high court", "atc", "election commission", "ecp",
    "imf", "un", "who", "world bank", "al qaeda", "taliban",
    "ary", "geo", "dawn", "bbc", "cnn", "aljazeera", "reuters", "ap",
}

_LOC_TERMS = {
    "pakistan", "islamabad", "lahore", "karachi", "peshawar", "quetta", "multan", "faisalabad", "rawalpindi",
    "sindh", "punjab", "kpk", "balochistan", "gilgit", "kashmir",
    "uk", "england", "london", "manchester", "birmingham",
    "usa", "united states", "washington", "new york",
    "india", "delhi", "bangladesh", "afghanistan", "iran", "china", "saudi", "uae", "dubai", "doha",
}


def _extract_person_names(text: str):
    t = (text or "").strip()
    if not t:
        return set()

    cands = re.findall(r"\b[A-Z][a-z]{2,}(?:\s+[A-Z][a-z]{2,}){1,2}\b", t)

    blacklist = {
        "Prime Minister",
        "Chief Minister",
        "United States",
        "United Kingdom",
        "Supreme Court",
        "High Court",
        "Pakistan Tehreek",
        "Tehreek E Insaf",
        "Pakistan Tehreek E",
        "Bank Alfalah",
    }

    out = set()
    for c in cands:
        c2 = c.strip()
        if c2 in blacklist:
            continue
        out.add(c2)
    return out


def _extract_numbers(text: str):
    t = (text or "").strip()
    if not t:
        return set()
    nums = re.findall(r"\b\d{1,4}\b", t)
    return set(nums)


def _extract_dates(text: str):
    t = normalize_text(text).lower()
    tokens = set()
    words = re.findall(r"[a-z]+|\d{1,4}", t)

    for i, w in enumerate(words):
        if w in _MONTHS:
            tokens.add(w)
            if i + 1 < len(words) and words[i + 1].isdigit():
                tokens.add(f"{w} {words[i+1]}")
        if w in _DAYS:
            tokens.add(w)
        if w.isdigit() and len(w) == 4 and (1900 <= int(w) <= 2100):
            tokens.add(w)

    pairs = re.findall(
        r"\b(\d{1,2})\s+(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\b",
        t,
    )
    for d, m in pairs:
        tokens.add(m)
        tokens.add(f"{m} {d}")

    return tokens


def _extract_locations(text: str):
    t = normalize_text(text).lower()
    out = set()
    for loc in _LOC_TERMS:
        if loc in t:
            out.add(loc)
    return out


def _extract_orgs(text: str):
    t = normalize_text(text).lower()
    out = set()
    for org in _ORG_TERMS:
        if org in t:
            out.add(org)
    return out


def _facts_from_text(text: str):
    return {
        "persons": _extract_person_names(text),
        "locations": _extract_locations(text),
        "dates": _extract_dates(text),
        "numbers": _extract_numbers(text),
        "orgs": _extract_orgs(text),
    }


def _match_set_ratio(claim_set, evidence_text_lower: str):
    if not claim_set:
        return set(), 1.0

    matched = set()
    for item in claim_set:
        if item.lower() in evidence_text_lower:
            matched.add(item)

    ratio = len(matched) / max(1, len(claim_set))
    return matched, float(ratio)


def _key_facts_guard(claim_text: str, evidence_text: str):
    claim_f = _facts_from_text(claim_text)
    ev_lower = (normalize_text(evidence_text) or "").lower()

    debug = {"claim": {}, "matched": {}, "ratios": {}, "groups_present": [], "groups_matched": []}

    groups_present = []
    groups_matched = []

    # persons
    if claim_f["persons"]:
        groups_present.append("persons")
        m, r = _match_set_ratio(claim_f["persons"], ev_lower)
        debug["claim"]["persons"] = sorted(claim_f["persons"])
        debug["matched"]["persons"] = sorted(m)
        debug["ratios"]["persons"] = r
        if len(m) >= 1 and (r >= MIN_GROUP_RATIO or len(claim_f["persons"]) == 1):
            groups_matched.append("persons")

    # locations
    if claim_f["locations"]:
        groups_present.append("locations")
        m, r = _match_set_ratio(claim_f["locations"], ev_lower)
        debug["claim"]["locations"] = sorted(claim_f["locations"])
        debug["matched"]["locations"] = sorted(m)
        debug["ratios"]["locations"] = r
        if len(m) >= 1:
            groups_matched.append("locations")

    # dates
    if claim_f["dates"]:
        groups_present.append("dates")
        m, r = _match_set_ratio(claim_f["dates"], ev_lower)
        debug["claim"]["dates"] = sorted(claim_f["dates"])
        debug["matched"]["dates"] = sorted(m)
        debug["ratios"]["dates"] = r
        if len(m) >= 1:
            groups_matched.append("dates")

    # numbers
    if claim_f["numbers"]:
        groups_present.append("numbers")
        m, r = _match_set_ratio(claim_f["numbers"], ev_lower)
        debug["claim"]["numbers"] = sorted(claim_f["numbers"])
        debug["matched"]["numbers"] = sorted(m)
        debug["ratios"]["numbers"] = r
        if len(m) >= 1:
            groups_matched.append("numbers")

    # orgs
    if claim_f["orgs"]:
        groups_present.append("orgs")
        m, r = _match_set_ratio(claim_f["orgs"], ev_lower)
        debug["claim"]["orgs"] = sorted(claim_f["orgs"])
        debug["matched"]["orgs"] = sorted(m)
        debug["ratios"]["orgs"] = r
        if len(m) >= 1 and (r >= MIN_GROUP_RATIO or len(claim_f["orgs"]) == 1):
            groups_matched.append("orgs")

    debug["groups_present"] = groups_present
    debug["groups_matched"] = groups_matched

    if not groups_present:
        return True, debug

    for g in HARD_GROUPS:
        if g in groups_present and g not in groups_matched:
            debug["hard_mismatch"] = g
            return False, debug

    ok = len(groups_matched) >= min(REQUIRE_GROUP_MATCHES, len(groups_present))
    return ok, debug


# -----------------------------
# Google Fact Check helpers (NEW)
# -----------------------------
def _rating_bucket(textual_rating: str) -> str:
    """
    Normalize many publishers' textual ratings into: true / false / mixed / unknown
    """
    r = (textual_rating or "").strip().lower()
    if not r:
        return "unknown"

    false_keys = [
        "false", "fake", "misleading", "incorrect", "pants on fire", "bogus", "hoax",
        "no evidence", "not true", "wrong", "scam",
    ]
    true_keys = [
        "true", "correct", "accurate", "yes", "fact", "genuine",
    ]
    mixed_keys = [
        "mixed", "partly", "partially", "half", "mostly", "needs context", "unproven",
        "misattributed", "outdated",
    ]

    if any(k in r for k in false_keys):
        return "false"
    if any(k in r for k in true_keys):
        return "true"
    if any(k in r for k in mixed_keys):
        return "mixed"
    return "unknown"


def _summarize_factcheck(fc_json: dict):
    """
    Returns: (bucket, evidence_list)
    evidence_list items are shaped for your ResultScreen matched_sources list.
    """
    if not fc_json or not isinstance(fc_json, dict):
        return "unknown", []

    claims = fc_json.get("claims") or []
    if not isinstance(claims, list) or not claims:
        return "unknown", []

    evidence = []
    buckets = []

    for c in claims[:5]:
        reviews = c.get("claimReview") or []
        if not isinstance(reviews, list):
            continue

        for rv in reviews[:3]:
            rating = rv.get("textualRating") or ""
            bucket = _rating_bucket(rating)
            if bucket != "unknown":
                buckets.append(bucket)

            url = (rv.get("url") or "").strip()
            publisher = (rv.get("publisher") or {}).get("name") or ""
            title = (c.get("text") or "").strip() or "Fact-check result"

            dom = ""
            if url:
                try:
                    from urllib.parse import urlparse
                    dom = (urlparse(url).netloc or "").replace("www.", "").lower()
                except Exception:
                    dom = ""

            evidence.append({
                "source": publisher,
                "domain": dom,
                "url": url,
                "publishedAt": rv.get("reviewDate") or None,
                "scrapedAt": None,
                "score": 95.0,
                "trusted": False,
                "type": "factcheck",
                "rating": rating,
                "title": title,
            })

    if not buckets:
        return "unknown", evidence

    # If conflicting signals exist, call it mixed
    if "true" in buckets and "false" in buckets:
        return "mixed", evidence

    # Majority vote
    from collections import Counter
    top = Counter(buckets).most_common(1)[0][0]
    return top, evidence


# -----------------------------
# Main API
# -----------------------------
def hybrid_decision(text: str, source_domain: str = ""):
    text = (text or "").strip()
    if not text:
        return {"error": True, "message": "Empty text"}

    link_domain = _norm_domain(source_domain) if source_domain else ""

    claim = normalize_text(clean_claim_text(text)).lower()
    query_used = claim

    if _looks_unstructured(text):
        return {
            "error": False,
            "final_label": "unverified",
            "final_confidence": float(CONF_LOW),
            "authenticity": "unverified",
            "confidence": float(CONF_LOW),
            "verdict_state": "not_verified",
            "verification_method": "input_too_vague",
            "source_tier": "unknown",
            "link_domain": link_domain,
            "final_reason": "Text is too incomplete/unclear to verify reliably. Add names, place, and what happened.",
            "query_used": query_used,
            "matches_found": 0,
            "matched_sources": [],
            "live_lookup": None,
            "facts_debug": None,
            "factcheck": None,
            "bert_label": None,
            "bert_confidence": None,
            "probabilities": None,
            "main_support_count": 0,
            "main_support_domains": [],
        }

    db = safe_read_db()
    matches = []
    soft_candidates = []

    for art in db:
        title = normalize_text(art.get("title", "")).lower()
        summary = normalize_text(art.get("summary", "")).lower()
        body = normalize_text(art.get("body", "")).lower()

        short_blob = f"{title} {summary}".strip()
        long_blob = f"{title} {summary} {body}".strip()

        s1 = score_match(claim, short_blob) if short_blob else 0.0
        s2 = score_match(claim, long_blob) if long_blob else 0.0
        score = max(s1, s2)

        soft_candidates.append((score, art))

        if score >= VERIFY_THRESHOLD:
            matches.append((score, art))

    matches.sort(key=lambda x: x[0], reverse=True)
    soft_candidates.sort(key=lambda x: x[0], reverse=True)
    soft_candidates = soft_candidates[:SOFT_CANDIDATE_TOPK]

    has_any_evidence = len(matches) > 0

    base_response = {
        "error": False,
        "final_label": "unverified",
        "final_confidence": float(CONF_LOW),
        "authenticity": "unverified",
        "confidence": float(CONF_LOW),
        "verdict_state": "not_verified",
        "verification_method": "no_evidence",
        "source_tier": "unknown",
        "link_domain": link_domain,
        "final_reason": "No sufficient evidence found.",
        "query_used": query_used,
        "matches_found": len(matches),
        "matched_sources": [],
        "live_lookup": None,
        "facts_debug": None,
        "factcheck": None,
        "bert_label": None,
        "bert_confidence": None,
        "probabilities": None,
        "main_support_count": 0,
        "main_support_domains": [],
    }

    # 2) SOFT PARAPHRASE MATCH + KEY FACTS GUARD
    if (not has_any_evidence) and soft_candidates:
        best_score, best_art = soft_candidates[0]

        if best_score >= SOFT_MATCH_MIN:
            dom = _norm_domain(best_art.get("domain") or "")
            trusted = _is_main_source_domain(dom)
            ev_text = _evidence_blob(best_art)

            if best_score >= SOFT_MATCH_STRONG:
                ok_facts, fact_dbg = _key_facts_guard(text, ev_text)
                if not ok_facts:
                    return {
                        **base_response,
                        "verification_method": "edited_claim_suspected",
                        "final_reason": (
                            "Similar coverage found, but key facts (person/place/date/number/org) don't match. "
                            "This looks like an edited claim, so we won't verify it."
                        ),
                        "facts_debug": fact_dbg,
                        "matched_sources": [
                            {
                                "source": best_art.get("source") or best_art.get("sourceName") or "",
                                "domain": dom,
                                "url": best_art.get("url") or "",
                                "publishedAt": best_art.get("publishedAt"),
                                "scrapedAt": best_art.get("scrapedAt"),
                                "score": float(best_score),
                                "trusted": trusted,
                                "type": "db",
                            }
                        ],
                    }

            if best_score < SOFT_MATCH_STRONG:
                return {
                    **base_response,
                    "verification_method": "weak_similar_coverage",
                    "source_tier": ("main" if trusted else "other"),
                    "final_reason": "We found somewhat similar coverage, but the match is not strong enough to verify.",
                    "matched_sources": [
                        {
                            "source": best_art.get("source") or best_art.get("sourceName") or "",
                            "domain": dom,
                            "url": best_art.get("url") or "",
                            "publishedAt": best_art.get("publishedAt"),
                            "scrapedAt": best_art.get("scrapedAt"),
                            "score": float(best_score),
                            "trusted": trusted,
                            "type": "db",
                        }
                    ],
                    "main_support_count": 1 if trusted else 0,
                    "main_support_domains": [dom] if trusted else [],
                }

            conf = float(CONF_SLIGHTLY_LOW if trusted else CONF_LOW)
            return {
                **base_response,
                "final_label": "real",
                "final_confidence": conf,
                "authenticity": "real",
                "confidence": conf,
                "verdict_state": "verified_real",
                "verification_method": "soft_db_match",
                "source_tier": ("main" if trusted else "other"),
                "final_reason": "Likely match: similar coverage found (paraphrase-tolerant).",
                "matched_sources": [
                    {
                        "source": best_art.get("source") or best_art.get("sourceName") or "",
                        "domain": dom,
                        "url": best_art.get("url") or "",
                        "publishedAt": best_art.get("publishedAt"),
                        "scrapedAt": best_art.get("scrapedAt"),
                        "score": float(best_score),
                        "trusted": trusted,
                        "type": "db",
                    }
                ],
                "main_support_count": 1 if trusted else 0,
                "main_support_domains": [dom] if trusted else [],
            }

    # 3) STRONG DB EVIDENCE -> REAL (also guard facts)
    if has_any_evidence:
        top_ev = _evidence_blob(matches[0][1])
        ok_facts, fact_dbg = _key_facts_guard(text, top_ev)

        if not ok_facts:
            return {
                **base_response,
                "verification_method": "edited_claim_suspected",
                "final_reason": (
                    "We found similar articles, but key facts (person/place/date/number/org) don't match. "
                    "This looks like an edited/altered claim, so we won't verify it."
                ),
                "facts_debug": fact_dbg,
                "matches_found": len(matches),
                "matched_sources": [
                    {
                        "source": a.get("source") or a.get("sourceName") or "",
                        "domain": _norm_domain(a.get("domain") or ""),
                        "url": a.get("url") or "",
                        "publishedAt": a.get("publishedAt"),
                        "scrapedAt": a.get("scrapedAt"),
                        "score": float(s),
                        "trusted": _is_main_source_domain(a.get("domain") or ""),
                        "type": "db",
                    }
                    for s, a in matches[:3]
                ],
            }

        domains = {_norm_domain(a.get("domain") or "") for _, a in matches[:5]}
        main_domains = {d for d in domains if _is_main_source_domain(d)}
        ms = len(main_domains)

        if ms >= 3:
            conf = float(CONF_HIGH)
            reason = "Verified: corroborated by 3+ main sources."
            tier = "main"
        elif ms >= 1:
            conf = float(CONF_SLIGHTLY_LOW)
            reason = "Verified: corroborated by 1–2 main sources."
            tier = "main"
        else:
            conf = float(CONF_LOW)
            reason = "Verified: corroborated by other news sources."
            tier = "other"

        return {
            **base_response,
            "final_label": "real",
            "final_confidence": conf,
            "authenticity": "real",
            "confidence": conf,
            "verdict_state": "verified_real",
            "verification_method": "db_match",
            "source_tier": tier,
            "final_reason": reason,
            "main_support_count": ms,
            "main_support_domains": list(main_domains),
            "matches_found": len(matches),
            "matched_sources": [
                {
                    "source": a.get("source") or a.get("sourceName") or "",
                    "domain": _norm_domain(a.get("domain") or ""),
                    "url": a.get("url") or "",
                    "publishedAt": a.get("publishedAt"),
                    "scrapedAt": a.get("scrapedAt"),
                    "score": float(s),
                    "trusted": _is_main_source_domain(a.get("domain") or ""),
                    "type": "db",
                }
                for s, a in matches[:5]
            ],
        }

    # -----------------------------
    # ✅ 3.5) GOOGLE FACT CHECK (NEW, minimal insertion)
    # Runs only when DB didn't verify and we are about to fallback.
    # -----------------------------
    fc_json = google_factcheck(query_used)
    if fc_json:
        bucket, fc_evidence = _summarize_factcheck(fc_json)
        if fc_evidence:
            if bucket == "false":
                return {
                    **base_response,
                    "final_label": "fake",
                    "final_confidence": float(CONF_HIGH),
                    "authenticity": "fake",
                    "confidence": float(CONF_HIGH),
                    "verdict_state": "verified_fake",
                    "verification_method": "google_factcheck",
                    "source_tier": "other",
                    "final_reason": "Verified as false based on published fact-check(s).",
                    "matched_sources": fc_evidence[:5],
                    "factcheck": {"bucket": bucket, "raw": fc_json},
                }
            if bucket == "true":
                return {
                    **base_response,
                    "final_label": "real",
                    "final_confidence": float(CONF_HIGH),
                    "authenticity": "real",
                    "confidence": float(CONF_HIGH),
                    "verdict_state": "verified_real",
                    "verification_method": "google_factcheck",
                    "source_tier": "other",
                    "final_reason": "Verified as true based on published fact-check(s).",
                    "matched_sources": fc_evidence[:5],
                    "factcheck": {"bucket": bucket, "raw": fc_json},
                }
            if bucket == "mixed":
                return {
                    **base_response,
                    "final_label": "mixed",
                    "final_confidence": float(CONF_SLIGHTLY_LOW),
                    "authenticity": "mixed",
                    "confidence": float(CONF_SLIGHTLY_LOW),
                    "verdict_state": "mixed",
                    "verification_method": "google_factcheck",
                    "source_tier": "other",
                    "final_reason": "Mixed/partial fact-check results found for this claim.",
                    "matched_sources": fc_evidence[:5],
                    "factcheck": {"bucket": bucket, "raw": fc_json},
                }
            # unknown bucket but evidence exists
            return {
                **base_response,
                "verification_method": "google_factcheck",
                "final_reason": "Fact-check results were found, but the rating is unclear. Review the sources.",
                "matched_sources": fc_evidence[:5],
                "factcheck": {"bucket": bucket, "raw": fc_json},
            }

    # -----------------------------
    # 4) NO DB -> LIVE GDELT LOOKUP (with safeguard)
    # -----------------------------
    claim_f = _facts_from_text(text)
    if claim_f["persons"] or claim_f["locations"] or claim_f["dates"] or claim_f["numbers"] or claim_f["orgs"]:
        return {
            **base_response,
            "verification_method": "no_text_evidence",
            "final_reason": (
                "No strong text evidence found for the exact claim. "
                "Only domain-level live signals are available, so we won't verify this."
            ),
        }

    live = gdelt_lookup_domains(text)

    if live.get("found_main"):
        ms = len(live.get("main_domains") or [])
        if ms >= 3:
            conf = float(CONF_HIGH)
            reason = "Verified (live): corroborated by 3+ main sources."
        elif ms >= 1:
            conf = float(CONF_SLIGHTLY_LOW)
            reason = "Verified (live): corroborated by 1–2 main sources."
        else:
            conf = float(CONF_LOW)
            reason = "Verified (live): corroborated by main sources."

        return {
            **base_response,
            "final_label": "real",
            "final_confidence": conf,
            "authenticity": "real",
            "confidence": conf,
            "verdict_state": "verified_real",
            "verification_method": "gdelt_main_sources",
            "source_tier": "main",
            "final_reason": reason,
            "main_support_count": ms,
            "main_support_domains": live.get("main_domains") or [],
            "live_lookup": live,
        }

    if live.get("found_other"):
        return {
            **base_response,
            "final_label": "real",
            "final_confidence": float(CONF_VERY_LOW),
            "authenticity": "real",
            "confidence": float(CONF_VERY_LOW),
            "verdict_state": "verified_real",
            "verification_method": "gdelt_other_major_sources",
            "source_tier": "other",
            "final_reason": "Verified (live): corroborated by other major news sources.",
            "live_lookup": live,
        }

    return base_response
