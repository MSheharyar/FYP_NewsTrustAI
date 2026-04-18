import re

VIRAL_NOISE_WORDS = {
    "breaking","viral","forward","fwd","shared","share","must","watch","alert","update",
    "just","now","today","yesterday","tomorrow","shocking","unbelievable","omg",
    "pls","please","kindly","urgent","warning","listen","important","attention",
    "confirm","confirmed","unconfirmed","sources","source","reportedly"
}

STOP_WORDS = {
    "the","a","an","and","or","to","of","in","on","for","with","is","are","was","were",
    "this","that","it","as","at","by","from","be","has","have","had","will","would",
    "can","could","should","may","might","about","into","over","after","before","than",
    "then","they","them","their","there","here","what","when","where","why","how",
    "you","your","we","our","i","he","she","his","her"
}

def normalize_text(text: str) -> str:
    if not text:
        return ""
    return " ".join(str(text).lower().split())

def clean_claim_text(text: str, max_chars: int = 260) -> str:
    t = (text or "").strip()
    t = re.sub(r"https?://\S+", " ", t)
    t = re.sub(r"[@#]\w+", " ", t)
    t = re.sub(r"\s+", " ", t).strip()

    if len(t) > max_chars:
        parts = re.split(r"(?<=[.!?])\s+", t)
        t = " ".join(parts[:2]).strip()
        if len(t) > max_chars:
            t = t[:max_chars].rsplit(" ", 1)[0].strip()

    return t

def extract_keywords(text: str, max_words: int = 14) -> str:
    t = clean_claim_text(text, max_chars=320)
    clean = "".join(ch if ch.isalnum() or ch.isspace() else " " for ch in t)
    clean = normalize_text(clean)
    words = [w for w in clean.split() if w]

    filtered = []
    for w in words:
        if len(w) < 4:
            continue
        if w in STOP_WORDS:
            continue
        if w in VIRAL_NOISE_WORDS:
            continue
        filtered.append(w)

    q = " ".join(filtered[:max_words]).strip()
    return q if q else normalize_text(t)