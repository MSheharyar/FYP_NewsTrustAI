import logging
import re
from concurrent.futures import ThreadPoolExecutor
from typing import Optional

import numpy as np
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from slowapi import Limiter
from slowapi.util import get_remote_address

from services.verification import hybrid_decision, _fuse_bert_with_hybrid
from services.bert import bert_predict
from services.urdu_bert import urdu_bert_predict, is_urdu
from services.lime_explainer import get_fake_highlights
from services.matching import score_match
from db.reader import get_candidate_articles
from text_verifier import get_text_verifier
from middleware.auth import require_firebase_auth

# One shared pool — avoids spinning up 2 threads per request.
_executor = ThreadPoolExecutor(max_workers=2)
limiter = Limiter(key_func=get_remote_address)

logger = logging.getLogger(__name__)
router = APIRouter()


class VerifyTextRequest(BaseModel):
    text: str = Field(..., min_length=1)
    query: Optional[str] = None


# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

def _make_predict_fn(text_is_urdu: bool):
    """
    Returns a predict_proba function for LIME with the language already fixed.
    Avoids re-running is_urdu() for every perturbation (300 calls per request).
    """
    def _predict(texts: list) -> np.ndarray:
        probs = []
        for t in texts:
            res = urdu_bert_predict(t) if text_is_urdu else bert_predict(t)
            pd = res.get("probabilities", {})
            probs.append([pd.get("fake", 0.5), pd.get("real", 0.5)])
        return np.array(probs)
    return _predict


def _make_db_search_fn():
    """
    Returns a BM25-backed search function for TextClaimVerifier.
    Retrieves the top-100 BM25 candidates, then scores each with RapidFuzz
    so the NLI stage gets ranked, relevant evidence instead of a full DB scan.
    """
    def db_search_fn(q: str):
        keywords = re.findall(r'\b[a-z]{3,}\b', q.lower())
        candidates = get_candidate_articles(keywords, top_k=100)
        results = []
        for art in candidates:
            blob = f"{art.get('title', '')} {art.get('summary', '')}".strip()
            score = score_match(q, blob)
            if score > 40:
                results.append({
                    "title":   art.get("title", ""),
                    "url":     art.get("url", ""),
                    "source":  art.get("sourceName", art.get("source", "")),
                    "snippet": art.get("summary", ""),
                    "score":   score,
                })
        results.sort(key=lambda x: x["score"], reverse=True)
        return results[:20]
    return db_search_fn


def _is_question(text: str) -> bool:
    """Return True when the input looks like a question rather than a falsifiable claim."""
    t = text.strip()
    if t.endswith('?'):
        return True
    lower = t.lower()
    starters = (
        'who ', 'what ', 'when ', 'where ', 'why ', 'how ', 'which ',
        'whose ', 'whom ', 'is ', 'are ', 'was ', 'were ', 'will ',
        'would ', 'could ', 'should ', 'can ', 'did ', 'does ', 'do ',
        'has ', 'have ',
    )
    return any(lower.startswith(s) for s in starters)


# Hybrid verdict methods that NLI should never override.
# These represent either authoritative external sources or deliberate rejections.
_NLI_SKIP_METHODS = {
    "input_too_vague",       # claim was too vague to search for
    "edited_claim_suspected", # key_facts_guard detected entity mismatch
    "google_factcheck",       # authoritative third-party fact-check
    "gdelt_main_sources",     # live GDELT signal from major outlets
    "gdelt_other_major_sources",
}


def _fuse_nli_with_hybrid(nli_res: dict, hybrid_res: dict) -> dict:
    """
    Merge the outputs of TextClaimVerifier (NLI) and hybrid_decision (RapidFuzz
    + fact-check + GDELT) using the following priority rules:

    1. Authoritative hybrid verdicts (fact-check, GDELT, edited-claim) → hybrid wins.
    2. Hybrid = UNVERIFIED + NLI decisive → NLI rescues the claim.
    3. Hybrid = REAL + NLI = FAKE (conf ≥ 0.75) → hybrid kept, disagreement flagged.
    4. Hybrid = REAL + NLI = REAL → NLI confirms, small confidence boost.
    5. All other cases → hybrid wins, NLI debug info attached.
    """
    hybrid_method = hybrid_res.get("verification_method", "")
    hybrid_label  = (hybrid_res.get("final_label") or "unverified").lower()
    nli_label     = (nli_res.get("final_label") or "UNVERIFIED").upper()
    nli_conf      = float(nli_res.get("final_confidence") or 0.0)
    nli_verified  = bool(nli_res.get("verified", False))

    # Rule 1 — never touch authoritative/rejected verdicts
    if hybrid_method in _NLI_SKIP_METHODS:
        hybrid_res["nli_debug"] = nli_res.get("nli", {})
        return hybrid_res

    # Rule 2 — NLI rescues an unverified claim
    if hybrid_label == "unverified" and nli_verified:
        label = nli_label.lower()
        return {
            **hybrid_res,
            "final_label":        label,
            "final_confidence":   nli_conf,
            "authenticity":       label,
            "confidence":         nli_conf,
            "verdict_state":      f"verified_{label}",
            "verification_method": "nli_semantic",
            "source_tier":        "main",
            "final_reason":       nli_res.get("explanation", ""),
            "matches_found":      len(nli_res.get("top_matches", [])),
            "matched_sources":    nli_res.get("top_matches", []),
            "nli_debug":          nli_res.get("nli", {}),
        }

    # Rule 3 — NLI contradicts hybrid's REAL verdict.
    #
    # Two tiers based on NLI confidence:
    #
    #  ≥ 0.85 (very high) → NLI overrides hybrid regardless of match strength.
    #          Rationale: the claim shares keywords with the article but says the
    #          opposite — a classic semantic inversion / fabricated claim.
    #
    #  0.75–0.85 (moderate) → flag disagreement only; hybrid verdict is kept.
    #          Rationale: avoid overriding strong multi-source evidence on a
    #          borderline NLI signal.
    if hybrid_label == "real" and nli_label == "FAKE" and nli_conf >= 0.75:
        if nli_conf >= 0.85:
            # NLI wins — semantic inversion detected
            label = "fake"
            return {
                **hybrid_res,
                "final_label":        label,
                "final_confidence":   round(nli_conf * 100, 1),
                "authenticity":       label,
                "confidence":         round(nli_conf * 100, 1),
                "verdict_state":      "verified_fake",
                "verification_method": "nli_contradiction",
                "final_reason": (
                    "The claim closely matches a real news story in structure and entities, "
                    "but semantically contradicts it — the key facts have been inverted. "
                    "This is likely a fabricated or misleading claim."
                ),
                "model_disagreement": True,
                "nli_debug":          nli_res.get("nli", {}),
                "matched_sources":    nli_res.get("top_matches", hybrid_res.get("matched_sources", [])),
            }
        # Moderate confidence — flag but keep hybrid verdict
        hybrid_res["model_disagreement"]  = True
        hybrid_res["verification_method"] = hybrid_method + "_nli_conflict"
        existing_reason = hybrid_res.get("final_reason") or ""
        hybrid_res["final_reason"] = (
            existing_reason.rstrip(". ") +
            ". Note: semantic analysis raised a contradiction — review matched sources carefully."
        )
        hybrid_res["nli_debug"] = nli_res.get("nli", {})
        return hybrid_res

    # Rule 4 — NLI confirms hybrid's REAL verdict
    if hybrid_label == "real" and nli_label == "REAL" and nli_verified:
        hybrid_res["verification_method"] = hybrid_method + "+nli"
        hybrid_res["nli_confirmed"]       = True
        boosted = min(float(hybrid_res.get("final_confidence", 0.0)) + 3.0, 95.0)
        hybrid_res["final_confidence"] = boosted
        hybrid_res["confidence"]       = boosted
        hybrid_res["nli_debug"]        = nli_res.get("nli", {})
        return hybrid_res

    # Rule 5 — default: hybrid result + NLI debug
    hybrid_res["nli_debug"] = nli_res.get("nli", {})
    return hybrid_res


# ─────────────────────────────────────────────────────────────
# Shared pipeline — imported by routes/links.py
# ─────────────────────────────────────────────────────────────

def run_full_pipeline(text: str) -> dict:
    """
    Full verification pipeline shared by /verify-text and /verify-link:
    language detection → NLI + Hybrid (parallel) → fuse → BERT → LIME.
    Returns a plain dict — HTTP exception handling is the caller's responsibility.
    """
    text_is_urdu = is_urdu(text)
    db_search_fn = _make_db_search_fn()

    nli_res    = {"verified": False, "final_label": "UNVERIFIED", "nli": {}}
    hybrid_res = {}

    try:
        if text_is_urdu:
            hybrid_res = _executor.submit(hybrid_decision, text).result(timeout=45)
        elif _is_question(text):
            future_hybrid = _executor.submit(hybrid_decision, text)
            hybrid_res = future_hybrid.result(timeout=45)
        else:
            verifier      = get_text_verifier()
            future_nli    = _executor.submit(verifier.verify, text, db_search_fn)
            future_hybrid = _executor.submit(hybrid_decision, text)
            nli_res    = future_nli.result(timeout=45)
            hybrid_res = future_hybrid.result(timeout=45)
    except Exception as exc:
        logger.warning("Parallel verification error (%s) — falling back to hybrid only.", exc)
        if not hybrid_res:
            hybrid_res = hybrid_decision(text)

    result = _fuse_nli_with_hybrid(nli_res, hybrid_res)

    result["detected_language"] = "urdu" if text_is_urdu else "english"
    bert_res = urdu_bert_predict(text) if text_is_urdu else bert_predict(text)

    result["bert_label"]      = bert_res.get("label")
    result["bert_confidence"] = float(bert_res.get("confidence") or 0.0)
    result["probabilities"]   = bert_res.get("probabilities")
    result["bert_note"]       = bert_res.get("note")

    if bert_res.get("label"):
        result = _fuse_bert_with_hybrid(result, bert_res)

    result["explanation_text"] = result.get("final_reason") or ""
    final_label = result.get("final_label", "unverified").lower()

    if final_label == "fake" and not text_is_urdu:
        result["highlighted_words"] = get_fake_highlights(
            text, _make_predict_fn(text_is_urdu), top_k=5
        )
        result["explanation_text"] = (
            "These words had the highest influence on our AI models "
            "in classifying this claim as Fake/Misleading."
        )
    else:
        result["highlighted_words"] = []
        if not result.get("explanation_text"):
            result["explanation_text"] = ""

    result.setdefault("error", False)
    return result


# ─────────────────────────────────────────────────────────────
# Route
# ─────────────────────────────────────────────────────────────

@router.post("/verify-text")
@limiter.limit("10/minute")
def verify_text(request: Request, payload: VerifyTextRequest, user: dict = Depends(require_firebase_auth)):
    text = (payload.text or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="Text is empty.")

    result = run_full_pipeline(text)

    if result.get("error") is True:
        raise HTTPException(
            status_code=400,
            detail=str(result.get("message") or result.get("explanation") or "Invalid input"),
        )

    return result
