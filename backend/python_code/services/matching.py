from rapidfuzz import fuzz

# Inversion-guard tuning: token_set_ratio ignores word order, so "A beat B"
# and "B beat A" both score ~100. These thresholds detect that pattern and
# blend in the raw character-level ratio to penalise inverted claims.
_INVERSION_BASE_THRESHOLD = 85   # trigger inversion check when base ≥ this
_INVERSION_RAW_THRESHOLD = 55    # only penalise when raw ratio < this
_INVERSION_BASE_WEIGHT = 0.65    # weight of base score in blended result
_INVERSION_RAW_WEIGHT = 0.35     # weight of raw ratio in blended result
_COMPARE_MAX_LEN = 200           # truncate both strings before raw comparison


def score_match(query: str, text: str) -> int:
    if not query or not text:
        return 0
    tset = fuzz.token_set_ratio(query, text)
    tsort = fuzz.token_sort_ratio(query, text)
    base = max(tset, tsort)

    if base >= _INVERSION_BASE_THRESHOLD:
        raw = fuzz.ratio(query[:_COMPARE_MAX_LEN], text[:_COMPARE_MAX_LEN])
        if raw < _INVERSION_RAW_THRESHOLD:
            return int(_INVERSION_BASE_WEIGHT * base + _INVERSION_RAW_WEIGHT * raw)

    return base
