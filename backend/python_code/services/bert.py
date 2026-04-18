from config.settings import MODEL_DIR
LABELS = {0: "fake", 1: "real"}
# Lazy-loaded globals
_TOKENIZER = None
_MODEL = None
_TORCH_OK = None
def _try_load():
    global _TOKENIZER, _MODEL, _TORCH_OK
    if _TORCH_OK is not None:
        return
    try:
        _MODEL.eval()
        _TORCH_OK = True
    except Exception:
        # Torch/transformers not available (or model missing) -> fallback mode
        _TOKENIZER = None
        _MODEL = None
        _TORCH_OK = False
def bert_predict(text: str):
    return {
        "label": "unverified",
        "confidence": 0.0,
        "probabilities": {"fake": 0.0, "real": 0.0},
        "note": "BERT disabled on this server (no torch/transformers).",
    }
