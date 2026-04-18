import re

def extract_entities(text: str, max_entities=6):
    if not text:
        return []
    candidates = re.findall(r"\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\b", text)
    seen = set()
    out = []
    for c in candidates:
        if c.lower() not in seen:
            seen.add(c.lower())
            out.append(c)
        if len(out) >= max_entities:
            break
    return out