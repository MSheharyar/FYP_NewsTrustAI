"""
services/facts.py
──────────────────
Key-facts extraction and guard logic, split out of verification.py.

Handles:
  - Named-entity extraction (persons, locations, orgs, dates, numbers, actions)
    Uses spaCy NER when available, falls back to regex/vocabulary approach.
  - _key_facts_guard: validates a claim's facts against evidence text
"""

import logging
import re
from utils.text import normalize_text

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────────────────────
# spaCy — loaded lazily; False means "tried and unavailable"
# ─────────────────────────────────────────────────────────────
_nlp = None

def _get_spacy():
    """Return a loaded spaCy nlp object, or None if unavailable."""
    global _nlp
    if _nlp is not None:
        return _nlp if _nlp is not False else None
    try:
        import spacy
        _nlp = spacy.load("en_core_web_sm")
        logger.info("spaCy en_core_web_sm loaded — using ML-based NER.")
        return _nlp
    except (ImportError, OSError):
        logger.warning(
            "spaCy / en_core_web_sm unavailable — using regex NER fallback. "
            "Install with: pip install spacy && python -m spacy download en_core_web_sm"
        )
        _nlp = False
        return None

# ─────────────────────────────────────────────────────────────
# Vocabulary sets
# ─────────────────────────────────────────────────────────────
_MONTHS = {
    "jan", "january", "feb", "february", "mar", "march", "apr", "april",
    "may", "jun", "june", "jul", "july", "aug", "august",
    "sep", "sept", "september", "oct", "october", "nov", "november",
    "dec", "december",
}

_DAYS = {"monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"}

_ORG_TERMS = {
    # Pakistan political
    "pti", "pmln", "pml-n", "ppp", "mqm", "anp", "jui", "tjp", "tehreek",
    # Pakistan institutions
    "army", "pakistan army", "isi", "police", "nab", "fbr", "fia",
    "supreme court", "high court", "lahore high court", "islamabad high court",
    "atc", "election commission", "ecp", "parliament", "senate", "national assembly",
    # International institutions
    "imf", "un", "who", "world bank", "nato", "eu", "european union",
    "world health organization", "wto", "unicef", "icc",
    # Militant/terror groups
    "al qaeda", "taliban", "isis", "isil", "ttp",
    # Media
    "ary", "geo", "dawn", "bbc", "cnn", "aljazeera", "reuters", "ap",
    "express", "samaa", "dunya", "express tribune",
    # Sports
    "pcb", "fifa", "icc",
}

_LOC_TERMS = {
    # Pakistan cities and regions
    "pakistan", "islamabad", "lahore", "karachi", "peshawar", "quetta",
    "multan", "faisalabad", "rawalpindi", "hyderabad", "sialkot", "gujranwala",
    "sindh", "punjab", "kpk", "balochistan", "gilgit", "kashmir", "azad kashmir",
    "swat", "waziristan",
    # UK
    "uk", "england", "london", "manchester", "birmingham", "britain", "scotland",
    # USA
    "usa", "united states", "america", "washington", "new york", "los angeles",
    "chicago", "texas", "florida", "california",
    # South Asia
    "india", "delhi", "mumbai", "new delhi", "kolkata", "bangalore",
    "bangladesh", "dhaka", "sri lanka", "nepal", "afghanistan", "kabul",
    "iran", "tehran",
    # Middle East
    "saudi", "saudi arabia", "riyadh", "uae", "dubai", "abu dhabi",
    "doha", "qatar", "kuwait", "jordan", "egypt", "cairo",
    "turkey", "ankara", "istanbul", "syria", "iraq", "baghdad",
    "israel", "gaza", "palestine", "lebanon", "beirut", "yemen",
    # Asia Pacific
    "china", "beijing", "shanghai", "hong kong", "taiwan",
    "japan", "tokyo", "south korea", "seoul", "malaysia", "singapore",
    # Europe / others
    "russia", "moscow", "ukraine", "kyiv", "france", "paris",
    "germany", "berlin", "italy", "rome",
    "canada", "toronto", "australia", "sydney",
}

_ACTION_TERMS = {
    # Death / killing
    "died", "dead", "death", "kills", "killed", "killing", "murder", "murders",
    "murdered", "murdering", "assassinated", "assassination", "executed", "execution",
    # Violence / attack
    "attack", "attacks", "attacked", "attacking", "bombed", "bombing",
    "blast", "blasts", "exploded", "explosion", "explosions",
    "shot", "shooting", "stabbed", "stabbing", "gunfire",
    # Arrest / legal
    "arrest", "arrests", "arrested", "arresting", "jailed", "imprisoned",
    "detained", "detention", "convicted", "sentenced", "acquitted", "indicted",
    # Employment / political
    "resigned", "resigns", "resign", "resignation", "fired", "sacked",
    "quit", "quits", "quitting", "banned", "suspended", "suspension",
    "appointed", "elected", "won", "wins", "lost", "loses", "defeated",
    "removed", "replaced", "ousted",
    # Personal
    "married", "marries", "marriage", "divorced", "divorcing",
    # Accident / disaster
    "crash", "crashed", "crashes", "accident", "accidents", "collision",
    "fire", "flood", "earthquake", "destroyed", "destroys",
    # Announcements
    "launched", "launches", "announced", "announces", "unveiled", "signed", "approved", "rejected",
}

# Guard tuning
MIN_GROUP_RATIO = 0.50
REQUIRE_GROUP_MATCHES = 2
HARD_GROUPS = {"numbers", "dates"}

# Blacklist for person name false-positives
_PERSON_BLACKLIST = {
    "Prime Minister", "Chief Minister", "United States", "United Kingdom",
    "Supreme Court", "High Court", "Pakistan Tehreek", "Tehreek E Insaf",
    "Pakistan Tehreek E", "Bank Alfalah",
}

# Title words that disqualify a regex match from being a real person name
_TITLE_WORDS = {
    "prime", "minister", "president", "chief", "general", "senator", "governor",
    "secretary", "justice", "judge", "ambassador", "commissioner", "director",
    "chairman", "deputy", "former", "federal", "provincial", "inspector",
    "colonel", "brigadier", "major", "captain", "doctor", "professor",
    "mister", "speaker", "advisor", "adviser", "minister", "member",
    "national", "international", "pakistani", "american", "british", "indian",
}


# ─────────────────────────────────────────────────────────────
# Extractors
# ─────────────────────────────────────────────────────────────
def extract_person_names(text: str) -> set:
    t = (text or "").strip()
    if not t:
        return set()
    cands = re.findall(r"\b[A-Z][a-z]{2,}(?:\s+[A-Z][a-z]{2,}){1,2}\b", t)
    result = set()
    for c in cands:
        c = c.strip()
        if not c or c in _PERSON_BLACKLIST:
            continue
        # Reject if any word in the matched phrase is a known title/adjective
        if any(w in _TITLE_WORDS for w in c.lower().split()):
            continue
        result.add(c)
    return result


def extract_numbers(text: str) -> set:
    t = (text or "").strip()
    if not t:
        return set()
    # Bare numbers (1-4 digits) — exclude 4-digit calendar years (handled via dates)
    nums = {n for n in re.findall(r"\b\d{1,4}\b", t)
            if not (len(n) == 4 and 1900 <= int(n) <= 2100)}
    # Number + unit context: "60 deaths", "10 gold", "22 percent"
    # Use max 3 digits for pairs (years never pair meaningfully with a unit word)
    pairs = re.findall(r"\b(\d{1,3})\s+([a-z]{3,15})\b", t.lower())
    for n, unit in pairs:
        nums.add(f"{n} {unit}")
    return nums


def extract_dates(text: str) -> set:
    t = normalize_text(text).lower()
    tokens: set = set()
    words = re.findall(r"[a-z]+|\d{1,4}", t)

    for i, w in enumerate(words):
        if w in _MONTHS:
            tokens.add(w)
            if i + 1 < len(words) and words[i + 1].isdigit():
                tokens.add(f"{w} {words[i + 1]}")
        if w in _DAYS:
            tokens.add(w)
        if w.isdigit() and len(w) == 4 and (1900 <= int(w) <= 2100):
            tokens.add(w)

    pairs = re.findall(
        r"\b(\d{1,2})\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may"
        r"|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?"
        r"|nov(?:ember)?|dec(?:ember)?)\b",
        t,
    )
    for d, m in pairs:
        tokens.add(m)
        tokens.add(f"{m} {d}")

    return tokens


def extract_locations(text: str) -> set:
    t = normalize_text(text).lower()
    return {loc for loc in _LOC_TERMS if re.search(r'\b' + re.escape(loc) + r'\b', t)}


def extract_orgs(text: str) -> set:
    t = normalize_text(text).lower()
    return {org for org in _ORG_TERMS if re.search(r'\b' + re.escape(org) + r'\b', t)}


def extract_actions(text: str) -> set:
    t = normalize_text(text).lower()
    return {act for act in _ACTION_TERMS if re.search(r'\b' + act + r'\b', t)}


def _facts_from_spacy(text: str, nlp) -> dict:
    """
    Extract entities using spaCy NER supplemented by regex/vocabulary results.

    spaCy excels at GPE/LOC/DATE but its small model has poor coverage of
    Pakistani person names and domain-specific organisations.  We take the
    union of both approaches so we never regress vs. the regex-only path.
    """
    doc = nlp(text)
    persons: set = set()
    locations: set = set()
    orgs: set = set()
    dates: set = set()
    numbers: set = set()

    for ent in doc.ents:
        val = ent.text.strip()
        if not val:
            continue
        label = ent.label_

        if label == "PERSON":
            # Apply same title-word filter used by the regex extractor
            if not any(w in _TITLE_WORDS for w in val.lower().split()):
                persons.add(val)
        elif label in ("GPE", "LOC", "FAC"):
            locations.add(val.lower())
        elif label == "ORG":
            orgs.add(val.lower())
        elif label in ("DATE", "TIME"):
            dates.add(val.lower())
        elif label in ("CARDINAL", "QUANTITY", "PERCENT", "MONEY"):
            # Keep only 1-4 digit integers (matches regex extractor behaviour)
            numbers.update(re.findall(r'\b\d{1,4}\b', val))

    # Supplement with regex/vocabulary results for Pakistan-specific coverage
    persons.update(extract_person_names(text))
    locations.update(extract_locations(text))
    orgs.update(extract_orgs(text))
    dates.update(extract_dates(text))
    numbers.update(extract_numbers(text))
    actions = extract_actions(text)

    return {
        "persons":   persons,
        "locations": locations,
        "dates":     dates,
        "numbers":   numbers,
        "orgs":      orgs,
        "actions":   actions,
    }


def facts_from_text(text: str) -> dict:
    """Extract named entities from text. Uses spaCy when installed, regex otherwise."""
    nlp = _get_spacy()
    if nlp:
        return _facts_from_spacy(text, nlp)
    return {
        "persons":   extract_person_names(text),
        "locations": extract_locations(text),
        "dates":     extract_dates(text),
        "numbers":   extract_numbers(text),
        "orgs":      extract_orgs(text),
        "actions":   extract_actions(text),
    }


# ─────────────────────────────────────────────────────────────
# Key-facts guard
# ─────────────────────────────────────────────────────────────
def _match_set_ratio(claim_set: set, ev_lower: str):
    if not claim_set:
        return set(), 1.0
    matched = {item for item in claim_set if item.lower() in ev_lower}
    return matched, len(matched) / max(1, len(claim_set))


def key_facts_guard(claim_text: str, evidence_text: str, claim_facts: dict = None):
    """
    Returns (ok: bool, debug: dict).
    ok=False means the facts in the claim don't match the evidence well
    enough — likely an edited / fabricated claim.

    Pass claim_facts to skip re-running NER when already computed by the caller.
    """
    claim_f = claim_facts if claim_facts is not None else facts_from_text(claim_text)
    ev_lower = (normalize_text(evidence_text) or "").lower()

    debug: dict = {"claim": {}, "matched": {}, "ratios": {}}
    groups_present: list = []
    groups_matched: list = []

    def _check(group: str, hard_fail: bool = False):
        items = claim_f.get(group) or set()
        if not items:
            return
        groups_present.append(group)
        matched, ratio = _match_set_ratio(items, ev_lower)
        debug["claim"][group] = sorted(items)
        debug["matched"][group] = sorted(matched)
        debug["ratios"][group] = ratio

        passes = len(matched) >= 1 and (ratio >= MIN_GROUP_RATIO or len(items) == 1)
        if passes:
            groups_matched.append(group)
        elif hard_fail:
            debug["hard_mismatch"] = group
            return True   # signal early exit
        return False

    # Persons and locations are hard failures
    for g in ("persons", "locations"):
        if _check(g, hard_fail=True) is True:
            return False, debug

    # Location ORDER check: if exactly 2 locations appear in reversed order
    # (e.g., claim says "India beat Pakistan" but evidence says "Pakistan beat India"),
    # flag as an entity-swapped claim — the inversion guard in score_match lowers
    # the fuzzy score but may not drop it below the verification threshold.
    _locations = claim_f.get("locations") or set()
    if len(_locations) == 2:
        _l1, _l2 = sorted(_locations)  # deterministic regardless of set hash order
        if _l1 in ev_lower and _l2 in ev_lower:
            _claim_lower = normalize_text(claim_text).lower()
            _p1c = _claim_lower.find(_l1)
            _p2c = _claim_lower.find(_l2)
            _p1e = ev_lower.find(_l1)
            _p2e = ev_lower.find(_l2)
            if all(p >= 0 for p in (_p1c, _p2c, _p1e, _p2e)):
                _claim_order = _p1c < _p2c
                _ev_order = _p1e < _p2e
                if _claim_order != _ev_order:
                    debug["hard_mismatch"] = "location_order_swapped"
                    return False, debug

    # Dates — only check specific month/day tokens; bare 4-digit years are too
    # ambiguous (a 2017 claim matched against a 2023 article fails unfairly).
    specific_dates = {d for d in (claim_f.get("dates") or set())
                      if not re.match(r'^\d{4}$', str(d))}
    if specific_dates:
        groups_present.append("dates")
        matched_d, ratio_d = _match_set_ratio(specific_dates, ev_lower)
        debug["claim"]["dates"]   = sorted(specific_dates)
        debug["matched"]["dates"] = sorted(matched_d)
        debug["ratios"]["dates"]  = ratio_d
        passes_d = len(matched_d) >= 1 and (ratio_d >= MIN_GROUP_RATIO or len(specific_dates) == 1)
        if passes_d:
            groups_matched.append("dates")
        else:
            debug["hard_mismatch"] = "dates"
            return False, debug

    _check("numbers")
    _check("orgs")

    # Actions: require majority match. Requiring ALL actions was too strict —
    # a claim like "arrested and resigned" fails if evidence only says "arrested".
    actions = claim_f.get("actions") or set()
    if actions:
        matched_a, ratio_a = _match_set_ratio(actions, ev_lower)
        debug["claim"]["actions"] = sorted(actions)
        debug["matched"]["actions"] = sorted(matched_a)
        debug["ratios"]["actions"] = ratio_a
        if not matched_a or ratio_a < MIN_GROUP_RATIO:
            debug["hard_mismatch"] = "actions"
            return False, debug

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
