import os
import threading
from typing import Any, Dict, Optional, Tuple

from config.settings import MODEL_DIR, BERT_MAX_LENGTH

LABELS = {0: "fake", 1: "real"}

_lock = threading.Lock()
_loaded: Optional[bool] = None
_load_note: str = ""
_tokenizer: Any = None
_model: Any = None
_device: str = "cpu"


def _model_source() -> Tuple[str, Dict[str, Any]]:
    """
    Decide where to load the model from.
    Priority:
    1) BERT_MODEL_NAME env (HuggingFace model id or local path)
    2) MODEL_DIR if it looks like a local HF folder
    """
    name = (os.getenv("BERT_MODEL_NAME") or "").strip()
    if name:
        return name, {}

    # If MODEL_DIR exists and looks like a HF directory, use it.
    if MODEL_DIR and os.path.isdir(MODEL_DIR):
        return MODEL_DIR, {"local_files_only": True}

    return "", {}


def _ensure_loaded() -> bool:
    """
    Load tokenizer+model once per process. Never reload per request.
    Returns True if model is available, otherwise False (fallback mode).
    """
    global _loaded, _load_note, _tokenizer, _model, _device

    if _loaded is not None:
        return bool(_loaded)

    with _lock:
        if _loaded is not None:
            return bool(_loaded)

        try:
            import torch  # type: ignore
            from transformers import AutoTokenizer, AutoModelForSequenceClassification  # type: ignore

            src, kwargs = _model_source()
            if not src:
                _loaded = False
                _load_note = "BERT disabled (no model configured)."
                return False

            _device = "cuda" if torch.cuda.is_available() else "cpu"

            _tokenizer = AutoTokenizer.from_pretrained(src, **kwargs)
            _model = AutoModelForSequenceClassification.from_pretrained(src, **kwargs).to(_device)
            _model.eval()

            _loaded = True
            _load_note = f"BERT loaded from {src} on {_device}."
            return True

        except Exception as e:
            _tokenizer = None
            _model = None
            _device = "cpu"
            _loaded = False
            _load_note = f"BERT disabled on this server ({e})."
            return False


def warmup_bert() -> Dict[str, Any]:
    """
    Called at startup to load the model (if possible).
    Returns a small status dict for logging/debug (not used by API directly).
    """
    ok = _ensure_loaded()
    return {"ok": ok, "device": _device, "note": _load_note}


def bert_predict(text: str) -> Dict[str, Any]:
    """
    Predict fake/real with a cached model. Falls back gracefully when unavailable.
    Output shape is kept stable for the Flutter client.
    """
    text = (text or "").strip()
    if not text:
        return {
            "label": "unverified",
            "confidence": 0.0,
            "probabilities": {"fake": 0.0, "real": 0.0},
            "note": "Empty text.",
        }

    if not _ensure_loaded():
        return {
            "label": "unverified",
            "confidence": 0.0,
            "probabilities": {"fake": 0.0, "real": 0.0},
            "note": _load_note or "BERT disabled on this server.",
        }

    try:
        import torch  # type: ignore

        assert _tokenizer is not None and _model is not None

        inputs = _tokenizer(
            text,
            truncation=True,
            max_length=BERT_MAX_LENGTH,
            return_tensors="pt",
        )
        inputs = {k: v.to(_device) for k, v in inputs.items()}

        with torch.inference_mode():
            logits = _model(**inputs).logits[0]
            probs = torch.softmax(logits, dim=-1).detach().float().cpu().tolist()

        # Defensive: ensure 2-class shape
        if not isinstance(probs, list) or len(probs) < 2:
            raise RuntimeError("Unexpected model output.")

        prob_fake = float(probs[0])
        prob_real = float(probs[1])
        label_id = 0 if prob_fake >= prob_real else 1
        label = LABELS.get(label_id, "unverified")
        confidence = max(prob_fake, prob_real)

        return {
            "label": label,
            "confidence": confidence,
            "probabilities": {"fake": prob_fake, "real": prob_real},
            "note": "",
        }
    except Exception as e:
        return {
            "label": "unverified",
            "confidence": 0.0,
            "probabilities": {"fake": 0.0, "real": 0.0},
            "note": f"BERT inference failed ({e}).",
        }
