import logging
import re
from datetime import datetime, timezone
from db.reader import safe_read_db, get_candidate_articles
from services.matching import score_match
from services.gdelt import gdelt_lookup_domains, CONF_VERY_LOW
from services.factcheck import google_factcheck
from services.facts import facts_from_text, key_facts_guard
from utils.text import clean_claim_text, normalize_text
from text_verifier import looks_unstructured
from config.settings import (
    VERIFY_THRESHOLD,
    CONF_HIGH,
    CONF_SLIGHTLY_LOW,
    CONF_LOW,
    MAIN_SOURCE_DOMAINS,
    MIN_TEXT_LEN,
    SOFT_CANDIDATE_TOPK,
    BERT_SUGGEST_REAL_THRESHOLD,
    BERT_SUSPECT_FAKE_THRESHOLD,
    BERT_DISAGREEMENT_THRESHOLD,
    STALE_THRESHOLD_DAYS,
)

logger = logging.getLogger(__name__)

SOFT_MATCH_MIN = float(max(0.30, VERIFY_THRESHOLD * 0.70))
SOFT_MATCH_STRONG = float(max(0.42, VERIFY_THRESHOLD * 0.85))


def _norm_domain(d: str) -> str:
    d = (d or "").strip().lower()
    if d.startswith("www."):
        d = d[4:]
    if d.startswith("m."):
        d = d[2:]
    if d == "edition.cnn.com":
        d = "cnn.com"
    return d


# Precomputed once at import time — avoids rebuilding the set on every article.
_MAIN_DOMAINS_NORM: frozenset = frozenset(_norm_domain(x) for x in MAIN_SOURCE_DOMAINS)


def _is_main_source_domain(d: str) -> bool:
    return _norm_domain(d) in _MAIN_DOMAINS_NORM


def _article_age_days(art: dict):
    """Return how many days old the article is, or None if date is missing/unparseable."""
    pub = art.get("publishedAt") or art.get("scrapedAt") or ""
    if not pub:
        return None
    try:
        dt = datetime.fromisoformat(str(pub).replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return (datetime.now(timezone.utc) - dt).days
    except (ValueError, TypeError):
        return None


def _evidence_blob(art: dict) -> str:
    title = normalize_text(art.get("title", ""))
    summary = normalize_text(art.get("summary", ""))
    body = normalize_text(art.get("body", ""))
    blob = f"{title}. {summary}. {body}".strip()
    return blob[:3000]


def _append_reason(base: str, addition: str) -> str:
    if not base:
        return addition.strip()
    base = base.strip()
    addition = addition.strip()
    if not addition:
        return base
    if base.endswith('.'):
        return f"{base} {addition}"
    return f"{base}. {addition}"


def _fuse_bert_with_hybrid(hybrid: dict, bert_res: dict) -> dict:
    if not isinstance(hybrid, dict):
        return hybrid

    bert_label = (bert_res.get("label") or "").lower()
    bert_confidence = float(bert_res.get("confidence") or 0.0)
    probabilities = bert_res.get("probabilities") or {}

    hybrid = dict(hybrid)
    hybrid["bert_label"] = bert_label or hybrid.get("bert_label")
    hybrid["bert_confidence"] = bert_confidence or hybrid.get("bert_confidence")
    hybrid["probabilities"] = probabilities
    hybrid["bert_note"] = bert_res.get("note") or hybrid.get("bert_note")
    hybrid["model_disagreement"] = hybrid.get("model_disagreement", False)

    if bert_label not in {"fake", "real"} or bert_confidence <= 0.0:
        return hybrid

    # Never override authoritative rejections with BERT
    _skip_methods = {"input_too_vague", "no_text_evidence", "no_evidence",
                     "edited_claim_suspected", "google_factcheck",
                     "gdelt_main_sources", "gdelt_other_major_sources"}
    if hybrid.get("verification_method", "") in _skip_methods:
        return hybrid

    final_label = (hybrid.get("final_label") or "").lower()

    if final_label == "unverified":
        if bert_label == "fake" and bert_confidence >= BERT_SUSPECT_FAKE_THRESHOLD:
            hybrid.update({
                "final_label": "fake",
                "final_confidence": float(CONF_LOW),
                "authenticity": "fake",
                "confidence": float(CONF_LOW),
                "verdict_state": "model_suspected_fake",
                "verification_method": "bert_only",
                "final_reason": _append_reason(
                    hybrid.get("final_reason", ""),
                    f"No strong external evidence was found, but the model predicts this claim is fake with {bert_confidence:.0%} confidence."
                ),
            })
        elif bert_label == "real" and bert_confidence >= BERT_SUGGEST_REAL_THRESHOLD:
            hybrid.update({
                "final_label": "real",
                "final_confidence": float(CONF_VERY_LOW),
                "authenticity": "real",
                "confidence": float(CONF_VERY_LOW),
                "verdict_state": "bert_suggested_real",
                "verification_method": "bert_suggested_real",
                "final_reason": _append_reason(
                    hybrid.get("final_reason", ""),
                    f"No strong external evidence was found, but the AI model suggests this claim is real with {bert_confidence:.0%} confidence. Treat with caution."
                ),
            })
        return hybrid

    if final_label == "real":
        if bert_label == "fake" and bert_confidence >= BERT_DISAGREEMENT_THRESHOLD:
            hybrid["model_disagreement"] = True
            hybrid["verification_method"] = "db_and_bert_conflict"
            hybrid["final_reason"] = _append_reason(
                hybrid.get("final_reason", ""),
                "A separate model check strongly disagrees and flags this claim as suspicious."
            )
        else:
            hybrid["verification_method"] = "db_and_bert"
        return hybrid

    if final_label == "fake":
        if bert_label == "real" and bert_confidence >= BERT_DISAGREEMENT_THRESHOLD:
            hybrid["model_disagreement"] = True
            hybrid["verification_method"] = "factcheck_and_bert_conflict"
            hybrid["final_reason"] = _append_reason(
                hybrid.get("final_reason", ""),
                "A separate model check suggests the claim may be real."
            )
        else:
            hybrid["verification_method"] = "factcheck_and_bert"
        return hybrid

    return hybrid




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

    if looks_unstructured(text):
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

    # Lazy fact extraction — spaCy NER is expensive; compute once and reuse.
    _claim_facts_cache: list = [None]

    def _get_claim_facts():
        if _claim_facts_cache[0] is None:
            _claim_facts_cache[0] = facts_from_text(text)
        return _claim_facts_cache[0]

    # Claims with fewer than 2 distinct named entities (person/location/org) are too
    # vague to trust database matching — skip BM25 and fall through to fact-check/GDELT.
    _cf_early = _get_claim_facts()
    _named_ent_count = (len(_cf_early["persons"])
                        + len(_cf_early["locations"])
                        + len(_cf_early["orgs"]))

    # Use the keyword index to pre-filter candidates instead of scanning the full DB
    claim_keywords = re.findall(r'\b[a-z]{4,}\b', claim.lower())
    if _named_ent_count >= 2:
        candidates = get_candidate_articles(claim_keywords) if claim_keywords else safe_read_db()
    else:
        candidates = []  # skip BM25 for low-entity claims; use fact-check fallback

    matches = []
    soft_candidates = []

    for art in candidates:
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
                ok_facts, fact_dbg = key_facts_guard(text, ev_text, claim_facts=_get_claim_facts())
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
            soft_reason = "Likely match: similar coverage found (paraphrase-tolerant)."

            # Staleness check for soft match
            soft_age = _article_age_days(best_art)
            soft_stale = soft_age is not None and soft_age > STALE_THRESHOLD_DAYS
            if soft_stale:
                soft_reason += (
                    f" Note: the matched article is ~{soft_age // 30} months old"
                    " — the current situation may have changed."
                )
                conf = max(conf - 7.0, float(CONF_LOW))

            return {
                **base_response,
                "final_label": "real",
                "final_confidence": conf,
                "authenticity": "real",
                "confidence": conf,
                "verdict_state": "verified_real",
                "verification_method": "soft_db_match",
                "source_tier": ("main" if trusted else "other"),
                "final_reason": soft_reason,
                "stale_evidence": soft_stale,
                "evidence_age_days": soft_age,
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
        ok_facts, fact_dbg = key_facts_guard(text, top_ev, claim_facts=_get_claim_facts())

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

        # Staleness check: downgrade confidence if best evidence is over 18 months old
        age_days = _article_age_days(matches[0][1])
        stale_evidence = age_days is not None and age_days > STALE_THRESHOLD_DAYS
        if stale_evidence:
            reason += (
                f" Note: the matched article is ~{age_days // 30} months old"
                " — the current situation may have changed."
            )
            conf = max(conf - 7.0, float(CONF_LOW))

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
            "stale_evidence": stale_evidence,
            "evidence_age_days": age_days,
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
    # 4) NO DB -> LIVE GDELT LOOKUP
    # -----------------------------
    # GDELT is a live news domain-coverage check — most useful for entity-rich
    # recent claims (persons, locations, orgs) where DB evidence is absent.
    # Run it for all claims that reach this point; skip only if the claim is
    # completely entity-free (likely too vague to get a meaningful GDELT signal).
    claim_f = _get_claim_facts()
    has_entities = bool(
        claim_f["persons"] or claim_f["locations"] or claim_f["dates"]
        or claim_f["numbers"] or claim_f["orgs"] or claim_f.get("actions")
    )
    if not has_entities:
        return {
            **base_response,
            "verification_method": "no_text_evidence",
            "final_reason": (
                "No strong text evidence found. The claim contains no named entities "
                "or facts that can be looked up in live news sources."
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
