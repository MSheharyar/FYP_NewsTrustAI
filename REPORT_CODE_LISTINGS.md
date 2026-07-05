# NewsTrustAI — Code Listings for the FYP Report

Curated, report-ready code excerpts. Each listing is trimmed of boilerplate
(marked `# …`) so it fits on a page. Line references point at the current
`main` branch.

**How to use this file**
- **Tier 1** → put these in the *Implementation / Methodology* chapter, in the body, each with a paragraph of explanation. They are the intellectual core of the system.
- **Tier 2** → put these in an *Appendix* and reference them from the body ("see Listing B.1").
- **Tier 3 (optional)** → short supporting excerpts, useful if you need to fill an appendix or explain a specific fix.
- Convention: introduce each listing in prose *above* it ("Listing 4.2 shows…") and place the *caption* below it. Use a monospace font at ~9–10 pt so lines don't wrap.

---

## Contents

**Tier 1 — Core contribution (body)**
1. [The verification pipeline orchestrator](#listing-1--the-verification-pipeline-orchestrator)
2. [Fusing evidence search with the NLI model](#listing-2--fusing-evidence-search-with-the-nli-model)
3. [The semantic-inversion guard in fuzzy matching](#listing-3--the-semantic-inversion-guard-in-fuzzy-matching)

**Tier 2 — Supporting depth (appendix)**
4. [Key-facts guard — edited-claim detection](#listing-4--key-facts-guard--edited-claim-detection)
5. [NLI semantic verification — weighted vote & consensus](#listing-5--nli-semantic-verification--weighted-vote--consensus)
6. [Hybrid decision — vagueness gate & candidate retrieval](#listing-6--hybrid-decision--vagueness-gate--candidate-retrieval)

**Tier 3 — Optional supporting excerpts**
7. [Input structure check (word-count based)](#listing-7--input-structure-check-word-count-based)
8. [Topic category classifier](#listing-8--topic-category-classifier)

---

# Tier 1 — Core contribution

## Listing 1 — The verification pipeline orchestrator
**Source:** `backend/python_code/routes/verify.py` · `run_full_pipeline()` (line 235)
**Placement:** Implementation chapter — this listing *is* your architecture in code.

```python
def run_full_pipeline(text: str) -> dict:
    text_is_urdu = is_urdu(text)                      # 1. language detection
    db_search_fn = _make_db_search_fn()

    if text_is_urdu or _is_question(text):
        # Urdu / questions: only the evidence-search branch runs
        par = run_parallel_verification(
            text, hybrid_fn=hybrid_decision,
            nli_fn=lambda t: {"verified": False, "final_label": "UNVERIFIED", "nli": {}})
        hybrid_res, nli_res = par["hybrid"], {"verified": False, "final_label": "UNVERIFIED"}
    else:
        # English: evidence-search and NLI run in parallel (ThreadPoolExecutor)
        verifier = get_text_verifier()
        par = run_parallel_verification(
            text, hybrid_fn=hybrid_decision,
            nli_fn=verifier.verify, db_search_fn=db_search_fn)   # 2. parallel branches
        hybrid_res, nli_res = par["hybrid"], par["nli"]

    result = _fuse_nli_with_hybrid(nli_res, hybrid_res)          # 3. fuse evidence + NLI
    result["detected_language"] = "urdu" if text_is_urdu else "english"

    bert_res = urdu_bert_predict(text) if text_is_urdu else bert_predict(text)  # 4. BERT
    result["bert_label"] = bert_res.get("label")
    result["bert_confidence"] = float(bert_res.get("confidence") or 0.0)
    if bert_res.get("label"):
        result = _fuse_bert_with_hybrid(result, bert_res)       # 5. add BERT signal

    if result.get("final_label") == "fake" and not text_is_urdu:
        result["highlighted_words"] = get_fake_highlights(      # 6. LIME (fake, English)
            text, _make_predict_fn(text_is_urdu), top_k=5)
    # … (result caching and explanation text omitted for brevity)
    return result
```

*Caption: The full verification pipeline. A claim flows through language detection, two parallel evidence branches (fuzzy database search + fact-check/GDELT, and NLI semantic verification), a rule-based fusion step, an independent BERT classifier, and LIME explainability for fake verdicts.*

**Report talking point:** emphasise that verification is *not* a single model call — it is an ensemble of retrieval, semantic entailment, and classification, combined by explicit logic, with Urdu and question inputs taking a safer single-branch path.

---

## Listing 2 — Fusing evidence search with the NLI model
**Source:** `backend/python_code/routes/verify.py` · `_fuse_nli_with_hybrid()` (line 133)
**Placement:** Implementation chapter, next to your fusion-rules table.

```python
def _fuse_nli_with_hybrid(nli_res: dict, hybrid_res: dict) -> dict:
    hybrid_method = hybrid_res.get("verification_method", "")
    hybrid_label  = (hybrid_res.get("final_label") or "unverified").lower()
    nli_label     = (nli_res.get("final_label") or "UNVERIFIED").upper()
    nli_conf      = float(nli_res.get("final_confidence") or 0.0)

    # Rule 1 — never override an authoritative verdict (fact-check, GDELT, edited-claim)
    if hybrid_method in _NLI_SKIP_METHODS:
        return hybrid_res

    # Rule 2 — NLI rescues a claim the evidence search left UNVERIFIED
    if hybrid_label == "unverified" and nli_res.get("verified"):
        return {**hybrid_res, "final_label": nli_label.lower(),
                "final_confidence": nli_conf, "verification_method": "nli_semantic",
                "matched_sources": nli_res.get("top_matches", [])}

    # Rule 3 — NLI contradicts a REAL verdict
    if hybrid_label == "real" and nli_label == "FAKE" and nli_conf >= 0.75:
        if nli_conf >= 0.85:                       # high conf → NLI overrides (inversion)
            return {**hybrid_res, "final_label": "fake",
                    "final_confidence": round(nli_conf * 100, 1),
                    "verification_method": "nli_contradiction", "model_disagreement": True}
        hybrid_res["model_disagreement"] = True    # moderate conf → flag, keep verdict
        return hybrid_res

    # Rule 4 — NLI confirms a REAL verdict → small confidence boost
    if hybrid_label == "real" and nli_label == "REAL" and nli_res.get("verified"):
        hybrid_res["nli_confirmed"] = True
        hybrid_res["final_confidence"] = min(hybrid_res.get("final_confidence", 0) + 3.0, 95.0)
        return hybrid_res

    return hybrid_res                              # Rule 5 — default: keep hybrid
```

*Caption: Rule-based fusion of the two evidence branches. Rather than averaging model scores, the system applies an ordered set of decision rules that respect authoritative sources, let semantic analysis rescue or override the fuzzy-match verdict, and surface genuine model–evidence disagreement to the user.*

**Report talking point:** a confidence-weighted override (≥ 0.85 overrides, 0.75–0.85 only flags) is a deliberate design choice — it avoids overturning strong multi-source evidence on a borderline model signal.

---

## Listing 3 — The semantic-inversion guard in fuzzy matching
**Source:** `backend/python_code/services/matching.py` · `score_match()` (line 13)
**Placement:** Implementation chapter — short, self-contained, and shows a genuine insight.

```python
def score_match(query: str, text: str) -> int:
    if not query or not text:
        return 0
    tset  = fuzz.token_set_ratio(query, text)      # ignores word order
    tsort = fuzz.token_sort_ratio(query, text)     # sorts tokens before comparing
    base  = max(tset, tsort)

    # "Pakistan beat India" vs "India beat Pakistan" both score ~100 above, so
    # fall back to the character-level ratio: a true inversion scores low there.
    if base >= 85:
        raw = fuzz.ratio(query[:200], text[:200])
        if raw < 55:
            return int(0.65 * base + 0.35 * raw)   # penalise the inverted claim
    return base
```

*Caption: The inversion guard. Order-insensitive fuzzy metrics rate "Pakistan beat India" and "India beat Pakistan" as identical; blending in the character-level ratio detects the reversal and lowers the score, preventing a fabricated claim from matching a real article.*

**Report talking point:** this directly addresses a failure mode of naive keyword matching for misinformation, where the *same words* in a different order flip the meaning.

---

# Tier 2 — Supporting depth (appendix)

## Listing 4 — Key-facts guard — edited-claim detection
**Source:** `backend/python_code/services/facts.py` · `key_facts_guard()` (line 305)
**Placement:** Appendix. Reference from the "altered real story" part of your methodology.

```python
def key_facts_guard(claim_text: str, evidence_text: str, claim_facts: dict = None):
    """Return (ok, debug). ok=False → the claim's facts don't match the evidence
    well enough — likely an edited / fabricated claim."""
    claim_f  = claim_facts if claim_facts is not None else facts_from_text(claim_text)
    ev_lower = (normalize_text(evidence_text) or "").lower()
    groups_present, groups_matched = [], []

    def _check(group, hard_fail=False):
        items = claim_f.get(group) or set()
        if not items:
            return False
        groups_present.append(group)
        matched, ratio = _match_set_ratio(items, ev_lower)
        if len(matched) >= 1 and (ratio >= MIN_GROUP_RATIO or len(items) == 1):
            groups_matched.append(group)
        elif hard_fail:
            return True                      # persons/locations mismatch → reject now
        return False

    # Persons and locations are hard requirements
    for g in ("persons", "locations"):
        if _check(g, hard_fail=True):
            return False, {"hard_mismatch": g}

    # Entity-order swap: "India beat Pakistan" vs "Pakistan beat India"
    locs = claim_f.get("locations") or set()
    if len(locs) == 2:
        l1, l2 = sorted(locs)
        if l1 in ev_lower and l2 in ev_lower:
            claim_order = normalize_text(claim_text).lower().find(l1) < normalize_text(claim_text).lower().find(l2)
            ev_order    = ev_lower.find(l1) < ev_lower.find(l2)
            if claim_order != ev_order:
                return False, {"hard_mismatch": "location_order_swapped"}

    _check("numbers"); _check("orgs")        # … dates and actions checked similarly

    # Majority rule: enough of the present fact-groups must match
    ok = len(groups_matched) >= min(REQUIRE_GROUP_MATCHES, len(groups_present))
    return ok, {"groups_present": groups_present, "groups_matched": groups_matched}
```

*Caption: The key-facts guard. After a fuzzy match is found, spaCy-extracted entities (persons, locations, numbers, organisations, dates, actions) are compared against the matched article. Person/location mismatches and reversed entity order are hard rejections; the remaining groups use a majority rule. This catches "altered real story" fakes that share wording with a genuine article but change a key fact.*

**Report talking point:** this is your defence against the most common Pakistani misinformation pattern — a real headline with one name, number, or place swapped.

---

## Listing 5 — NLI semantic verification — weighted vote & consensus
**Source:** `backend/python_code/text_verifier.py` · `TextClaimVerifier.verify()` (line 201)
**Placement:** Appendix. Reference from the semantic-verification part of your methodology.

```python
def verify(self, user_text, search_fn, min_semantic=0.55,
           entail_threshold=0.70, contradict_threshold=0.70):
    queries, extracted_claim = build_search_queries(user_text)
    evidence = self._to_evidence(dedup_by_url(collect(search_fn, queries)))
    if not evidence:
        return {"verified": False, "final_label": "UNVERIFIED", "top_matches": []}

    # 1) Semantic re-rank for paraphrase robustness; drop weak matches
    ranked_sem = [(e, s) for (e, s) in self.semantic_rerank(extracted_claim, evidence)
                  if s >= min_semantic][:max_evidence]

    # 2) NLI batch scoring + confidence-and-similarity-weighted vote
    premises   = [normalize_spaces(e.title + " " + e.snippet) for e, _ in ranked_sem]
    nli_results = self.nli_score_batch(extracted_claim, premises)
    entail_score = contra_score = 0.0
    best_entail  = best_contra  = {"conf": 0.0, "semantic": 0.0}
    for (label, conf), (e, sem) in zip(nli_results, ranked_sem):
        weight = conf * (0.7 + 0.3 * sem)          # trust ∝ confidence × similarity
        if label == "ENTAILMENT":
            entail_score += weight
            if conf > best_entail["conf"]: best_entail = {"conf": conf, "semantic": sem}
        elif label == "CONTRADICTION":
            contra_score += weight
            if conf > best_contra["conf"]: best_contra = {"conf": conf, "semantic": sem}

    # 3) Consensus: the winner must dominate (ratio) or be the only signal
    total        = entail_score + contra_score
    entail_ratio = entail_score / total if total else 0.5

    # 4) Decision policy
    if best_entail["conf"] >= entail_threshold and (entail_ratio >= 0.55 or contra_score == 0):
        conf = min(0.95, 0.60 + 0.35 * best_entail["conf"] + 0.10 * best_entail["semantic"])
        return {"final_label": "REAL",  "verified": True,  "final_confidence": conf}
    if best_contra["conf"] >= contradict_threshold and (entail_ratio <= 0.45 or entail_score == 0):
        conf = min(0.95, 0.60 + 0.35 * best_contra["conf"] + 0.10 * best_contra["semantic"])
        return {"final_label": "FAKE",  "verified": True,  "final_confidence": conf}
    return {"final_label": "UNVERIFIED", "verified": False}
    # (The full method also tries up to two sentence candidates and keeps the
    #  one with the strongest decisive signal, so a neutral first sentence can't
    #  mask a false second one.)
```

*Caption: NLI-based semantic verification. Retrieved evidence is re-ranked by embedding similarity, then each premise is scored by a Natural Language Inference cross-encoder. Votes are weighted by (NLI confidence × semantic similarity); a verdict is only issued when the winning direction dominates the total or is the sole signal, otherwise the claim stays UNVERIFIED.*

**Report talking point:** the weighting and the ≥ 55% dominance ratio are what stop a single loosely-related article from producing a false "verified".

---

## Listing 6 — Hybrid decision — vagueness gate & candidate retrieval
**Source:** `backend/python_code/services/verification.py` · `hybrid_decision()` (line 268, excerpted)
**Placement:** Appendix. Show *only* this excerpt — the full function is ~350 lines.

```python
def hybrid_decision(text: str, source_domain: str = ""):
    claim = normalize_text(clean_claim_text(text)).lower()

    if looks_unstructured(text):                     # too short/vague to search
        return {"final_label": "unverified", "verification_method": "input_too_vague",
                "final_reason": "Text is too incomplete/unclear to verify reliably."}

    # Lazy NER — spaCy is expensive, so extract entities once and reuse.
    cf = facts_from_text(text)
    named_ent_count = len(cf["persons"]) + len(cf["locations"]) + len(cf["orgs"])

    # Run the DB search when the claim has 2+ named entities OR is keyword-rich.
    # (spaCy misses lowercase/foreign names, so keyword-rich headlines still search.)
    claim_keywords = re.findall(r'\b[a-z]{4,}\b', claim)
    if named_ent_count >= 2 or len(set(claim_keywords)) >= 4:
        candidates = get_candidate_articles(claim_keywords) if claim_keywords else safe_read_db()
    else:
        candidates = []

    matches, soft_candidates = [], []
    for art in candidates:
        blob  = f"{art.get('title','')} {art.get('summary','')}".lower()
        score = score_match(claim, blob)             # fuzzy score + inversion guard
        soft_candidates.append((score, art))
        if score >= VERIFY_THRESHOLD:                # strong match
            matches.append((score, art))
    # … strong matches then run key_facts_guard(); soft matches → soft_db_match;
    #    if the DB yields nothing → Google Fact Check → GDELT → final "unverified"
```

*Caption: The evidence-search entry point. A claim is gated for searchability, entities are extracted once (cached), and candidate articles are retrieved by BM25 only when the claim has enough named entities or distinct keywords. Each candidate is scored with the inversion-aware `score_match`; strong matches are then validated by the key-facts guard.*

**Report talking point:** the "≥ 2 entities OR ≥ 4 keywords" gate balances precision (don't search on vague input) against recall (spaCy misses valid entities, so keyword-rich headlines still get searched).

---

# Tier 3 — Optional supporting excerpts

## Listing 7 — Input structure check (word-count based)
**Source:** `backend/python_code/text_verifier.py` · `looks_unstructured()` (line 90)
**Placement:** Optional appendix / a "robustness" subsection.

```python
def looks_unstructured(text: str) -> bool:
    text = normalize_spaces(text)
    # Count real words (Latin OR Urdu/Arabic script). Enough words => searchable,
    # regardless of capitalisation — news headlines are often short and/or lowercase.
    word_count = len(re.findall(r"[A-Za-z؀-ۿ]{2,}", text))

    if word_count < 4 and len(text) < MIN_TEXT_LEN:          # genuinely too short
        return True
    if len(_EMOJI_RE.findall(text)) >= 2:                    # spam / slang
        return True
    non_alnum = sum(1 for c in text if not c.isalnum() and c not in " .,:;!?-'\"()")
    if non_alnum > 18:                                       # symbol soup
        return True
    has_caps = bool(re.search(r"\b[A-Z][a-z]{2,}\b", text))
    has_num  = bool(re.search(r"\d", text))
    if not has_caps and not has_num and word_count < 5 and len(text) < 60:
        return True
    return False
```

*Caption: The input-structure check. Searchability is judged primarily by word count (Latin or Urdu script) rather than capitalisation, so a normal lowercase headline is accepted while genuine junk (very short, emoji-only, or symbol soup) is rejected.*

---

## Listing 8 — Topic category classifier
**Source:** `backend/python_code/routes/trending.py` · `_categorize()`
**Placement:** Optional appendix / the "news feed" feature description.

```python
_CATEGORY_KEYWORDS = {
    "Sports":     ["cricket", "football", "tennis", "world cup", "wicket", ...],
    "Business":   ["economy", "market", "budget", "inflation", "rupee", ...],
    "Technology": ["software", "artificial intelligence", "google", "iphone", ...],
    "Politics":   ["politic", "government", "election", "parliament", "trump", ...],
    "World":      ["gaza", "israel", "ukraine", "china", "military", ...],
    # … Entertainment, Health, plus Urdu keywords per category
}

def _categorize(title: str, summary: str) -> str:
    text = f"{title} {summary}".lower()
    best_cat, best_score = "General", 0
    for cat, kws in _CATEGORY_KEYWORDS.items():
        score = sum(1 for kw in kws if kw in text)   # count keyword hits
        if score > best_score:
            best_cat, best_score = cat, score
    return best_cat
```

*Caption: The topic classifier. Because the RSS data has no category field, each article is tagged by scoring its title and summary against per-topic keyword lists (English and Urdu) and choosing the highest-scoring topic, or "General" when none match. This powers the category filter pills on the All News screen.*

---

*Generated as a companion to `SYSTEM_DOCUMENTATION.md` for the NewsTrustAI FYP report.*
