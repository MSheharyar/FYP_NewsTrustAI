from rapidfuzz import fuzz

def score_match(query: str, text: str) -> int:
    if not query or not text:
        return 0
    # Avoid partial_ratio because it stays high even when the user edits
    # a claim (e.g., changes a person/place/date) but keeps most words.
    return max(
        fuzz.token_set_ratio(query, text),
        fuzz.token_sort_ratio(query, text),
    )
