"""
services/urdu_bert.py
─────────────────────
Urdu fake-news detection via the HuggingFace Inference API.
No model files are stored on the server — zero disk cost.

Setup:
  Set the HF_API_TOKEN environment variable with a free token from:
  https://huggingface.co/settings/tokens

  Optionally override the model:
  export URDU_MODEL_ID="ikomil/bert-urdu-fake-news"
"""

import re
from typing import Dict, Any

from config.settings import HF_API_TOKEN, URDU_MODEL_ID, HF_REQUEST_TIMEOUT, ROMAN_URDU_THRESHOLD
from services.http_client import safe_post_json

HF_API_URL = f"https://api-inference.huggingface.co/models/{URDU_MODEL_ID}"

# Maps HuggingFace label strings → our internal labels
_LABEL_MAP = {
    "LABEL_0": "fake", "LABEL_1": "real",
    "fake": "fake",    "real": "real",
    "FAKE": "fake",    "REAL": "real",
    "0": "fake",       "1": "real",
}

# ─────────────────────────────────────────────────────────────
# Language detection
# ─────────────────────────────────────────────────────────────
_ROMAN_URDU_WORDS = {
    "hai", "hain", "tha", "thi", "ka", "ki", "ke", "ko", "ne",
    "se", "mein", "par", "aur", "ya", "bhi", "nahi", "nahin", "koi",
    "kuch", "yeh", "woh", "ap", "aap", "hum", "tum", "mai",
    "agar", "lekin", "magar", "phir", "ab", "abhi", "sirf", "bas",
    "kya", "kyun", "kaise", "kahan", "kab", "kaun", "kitna", "kitne",
    "kal", "aaj", "raat", "log", "baat", "waqt", "jagah",
    "sarkaar", "sarkar", "hakumat", "hukumat", "awaam", "awam",
    "ijtima", "masjid", "namaz", "roza", "hadees",
}
def is_urdu(text: str) -> bool:
    """
    Returns True when the text is Urdu — either script or Romanised.

    Primary check: Unicode block U+0600–U+06FF (Arabic/Urdu script).
    Secondary check: count of known Romanised Urdu words; three or more
    matches routes the text to the Urdu BERT model instead of English BERT.
    """
    if bool(re.search(r'[؀-ۿ]', text or "")):
        return True
    tokens = re.findall(r"[a-z]+", (text or "").lower())
    hits = sum(1 for t in tokens if t in _ROMAN_URDU_WORDS)
    return hits >= ROMAN_URDU_THRESHOLD


# ─────────────────────────────────────────────────────────────
# Urdu prediction
# ─────────────────────────────────────────────────────────────
def urdu_bert_predict(text: str) -> Dict[str, Any]:
    """
    Calls the HuggingFace Inference API to classify Urdu text as fake/real.

    Returns the same dict shape as bert_predict() so it is a drop-in
    replacement in routes/verify.py.

    Fallback: returns label="unverified" on any error so the app keeps
    working even if the API is unavailable or the token is missing.
    """
    text = (text or "").strip()

    if not text:
        return _fallback("Empty text.")

    if not HF_API_TOKEN:
        return _model_unavailable()

    headers = {"Authorization": f"Bearer {HF_API_TOKEN}"}
    payload = {"inputs": text, "options": {"wait_for_model": True}}

    data = safe_post_json(HF_API_URL, json_body=payload, headers=headers,
                          timeout=HF_REQUEST_TIMEOUT)
    if data is None:
        return _model_unavailable()

    try:
        # HuggingFace returns one of two shapes:
        #   [[{"label": "LABEL_0", "score": 0.92}, ...]]   ← text-classification
        #   [{"label": "LABEL_0", "score": 0.92}, ...]     ← some models
        items = data[0] if (isinstance(data, list) and isinstance(data[0], list)) else data

        if not isinstance(items, list):
            return _fallback(f"Unexpected API response shape: {data}")

        # Build a scores dict keyed by our internal labels
        scores: Dict[str, float] = {}
        for item in items:
            mapped = _LABEL_MAP.get(item.get("label", ""), "")
            if mapped:
                scores[mapped] = float(item.get("score", 0.0))

        if not scores:
            return _fallback(f"Could not map API labels. Raw: {items}")

        prob_fake = scores.get("fake", 0.0)
        prob_real = scores.get("real", 0.0)

        # Normalise in case probabilities don't sum to 1
        total = prob_fake + prob_real
        if total > 0:
            prob_fake /= total
            prob_real /= total

        label = "fake" if prob_fake >= prob_real else "real"
        confidence = max(prob_fake, prob_real)

        return {
            "label": label,
            "confidence": round(confidence, 4),
            "probabilities": {
                "fake": round(prob_fake, 4),
                "real": round(prob_real, 4),
            },
            "note": "urdu_hf_api",
        }

    except Exception as e:
        return _fallback(f"Urdu model error: {e}")


def _model_unavailable() -> Dict[str, Any]:
    """Returned when the HF token is missing or the API call failed."""
    return {
        "label": "unverified",
        "confidence": 0.0,
        "probabilities": {"fake": 0.0, "real": 0.0},
        "note": "urdu_model_unavailable",
    }


def _fallback(note: str) -> Dict[str, Any]:
    """Consistent unverified fallback with a note explaining why."""
    return {
        "label": "unverified",
        "confidence": 0.0,
        "probabilities": {"fake": 0.0, "real": 0.0},
        "note": note,
    }
