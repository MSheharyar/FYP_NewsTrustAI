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
9. [Bilingual language detection (Urdu script + Romanised)](#listing-9--bilingual-language-detection-urdu-script--romanised)

**Tier 2 — Supporting depth (appendix)**
4. [Key-facts guard — edited-claim detection](#listing-4--key-facts-guard--edited-claim-detection)
5. [NLI semantic verification — weighted vote & consensus](#listing-5--nli-semantic-verification--weighted-vote--consensus)
6. [Hybrid decision — vagueness gate & candidate retrieval](#listing-6--hybrid-decision--vagueness-gate--candidate-retrieval)
10. [Parallel verification with graceful degradation](#listing-10--parallel-verification-with-graceful-degradation)
11. [Fusing the BERT classifier](#listing-11--fusing-the-bert-classifier)

**Explainability (XAI section)**
12. [LIME word-importance highlights](#listing-12--lime-word-importance-highlights)

**Frontend (if you have a frontend chapter)**
13. [Client-side defensive result parsing](#listing-13--client-side-defensive-result-parsing)

**News feed (if highlighted as a feature)**
14. [Trending freshness selection](#listing-14--trending-freshness-selection)

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

# Additional listings

## Listing 9 — Bilingual language detection (Urdu script + Romanised)
**Source:** `backend/python_code/services/urdu_bert.py` · `is_urdu()` (line 44)
**Placement:** Tier 1 / Implementation chapter — a distinctive, Pakistan-specific feature.

```python
# Romanised-Urdu markers — how Pakistanis actually type on WhatsApp / social media
_ROMAN_URDU_WORDS = {
    "hai", "hain", "ka", "ki", "ke", "ko", "ne", "se", "mein", "par", "aur",
    "nahi", "nahin", "yeh", "woh", "aap", "hum", "kya", "kyun", "kaise",
    "sarkar", "hukumat", "awam", "masjid", "namaz", # … ~80 words total
}

def is_urdu(text: str) -> bool:
    """True when the text is Urdu — either native script or Romanised."""
    # Primary: any character in the Arabic/Urdu Unicode block (U+0600–U+06FF)
    if bool(re.search(r'[؀-ۿ]', text or "")):
        return True
    # Secondary: 3+ known Romanised-Urdu words → route to the Urdu model
    tokens = re.findall(r"[a-z]+", (text or "").lower())
    hits = sum(1 for t in tokens if t in _ROMAN_URDU_WORDS)
    return hits >= ROMAN_URDU_THRESHOLD
```

*Caption: Bilingual language detection. Urdu is detected two ways — by the presence of Arabic/Urdu-script characters, and by a word-list of common Romanised-Urdu terms (the way Urdu is typed in Latin letters on messaging apps). This routes each claim to the correct model (Urdu BERT vs English BERT) and disables NLI/LIME for script that the English pipeline cannot process.*

**Report talking point:** most fake-news systems assume a single language; supporting *both* Urdu script and Romanised Urdu is a direct response to how misinformation actually circulates in Pakistan.

---

## Listing 10 — Parallel verification with graceful degradation
**Source:** `backend/python_code/routes/verify.py` · `run_parallel_verification()` (line 31)
**Placement:** Tier 2 / a *performance & reliability* subsection.

```python
def run_parallel_verification(text, hybrid_fn, nli_fn, db_search_fn=None):
    """Run the hybrid and NLI branches in parallel. If either raises, capture
    None for that side and flag the result as degraded, so the request still
    returns a verdict instead of failing."""
    def _safe(fn, *args):
        try:
            return fn(*args), None
        except Exception as exc:
            logger.exception("verification thread failed: %s", fn)
            return None, exc

    fut_hybrid = _executor.submit(_safe, hybrid_fn, text)          # thread A
    fut_nli    = _executor.submit(_safe, nli_fn, text, db_search_fn) \
                 if db_search_fn is not None else _executor.submit(_safe, nli_fn, text)

    hybrid_res, hybrid_err = fut_hybrid.result()                   # thread B
    nli_res,    nli_err    = fut_nli.result()
    return {"hybrid": hybrid_res, "nli": nli_res,
            "degraded": bool(hybrid_err) or bool(nli_err)}
```

*Caption: Parallel branch execution with graceful degradation. The evidence-search and NLI branches run concurrently on a shared thread pool, so wall-clock latency is max(t_hybrid, t_nli) rather than their sum. If one branch throws, its result is captured as None and the response is marked `degraded`, guaranteeing the user always gets a verdict.*

**Report talking point:** this is a reliability decision — a single failing model must not take down the whole verification.

---

## Listing 11 — Fusing the BERT classifier
**Source:** `backend/python_code/services/verification.py` · `_fuse_bert_with_hybrid()` (line 84, excerpted)
**Placement:** Tier 2 / appendix — companion to Listing 2 (which fuses NLI).

```python
def _fuse_bert_with_hybrid(hybrid: dict, bert_res: dict) -> dict:
    bert_label = (bert_res.get("label") or "").lower()
    bert_confidence = float(bert_res.get("confidence") or 0.0)

    # Never let BERT override an authoritative verdict (fact-check, GDELT, too-vague…)
    if hybrid.get("verification_method") in _SKIP_METHODS or bert_label not in {"fake", "real"}:
        return hybrid

    final_label = (hybrid.get("final_label") or "").lower()

    if final_label == "unverified":                     # no external evidence found
        if bert_label == "fake" and bert_confidence >= BERT_SUSPECT_FAKE_THRESHOLD:   # ≥ 0.88
            hybrid.update(final_label="fake", verification_method="bert_only",
                          final_confidence=float(CONF_LOW))
        elif bert_label == "real" and bert_confidence >= BERT_SUGGEST_REAL_THRESHOLD: # ≥ 0.90
            hybrid.update(final_label="real", verification_method="bert_suggested_real",
                          final_confidence=float(CONF_VERY_LOW))
        return hybrid

    if final_label == "real":                           # evidence says real
        if bert_label == "fake" and bert_confidence >= BERT_DISAGREEMENT_THRESHOLD:   # ≥ 0.92
            hybrid["model_disagreement"] = True          # flag, but keep the evidence verdict
            hybrid["verification_method"] = "db_and_bert_conflict"
        else:
            hybrid["verification_method"] = "db_and_bert"
    return hybrid
```

*Caption: Folding the BERT classifier into the verdict. BERT is treated as a secondary signal: it can promote an otherwise-unverified claim (its confidence sets a deliberately capped confidence), but it can only flag disagreement — never silently override — a verdict already backed by external evidence. Authoritative methods are skipped entirely.*

**Report talking point:** the asymmetry (BERT decides only when there is no evidence, otherwise it just flags) prevents a black-box model from overturning transparent, source-backed verdicts.

---

## Listing 12 — LIME word-importance highlights
**Source:** `backend/python_code/services/lime_explainer.py` · `get_fake_highlights()` (line 17)
**Placement:** Explainable-AI section.

```python
# LIME on CPU is expensive (one BERT call per perturbation); 50–100 samples is a
# stable trade-off for top-5 highlights. Overridable via LIME_NUM_SAMPLES.
_NUM_SAMPLES = int(os.getenv("LIME_NUM_SAMPLES", "50"))
explainer = LimeTextExplainer(class_names=['fake', 'real'])   # class 0 = fake

def get_fake_highlights(text: str, predict_proba_fn, top_k: int = 5) -> list:
    """Return the words that pushed the model towards a 'fake' verdict."""
    try:
        exp = explainer.explain_instance(
            text, predict_proba_fn, labels=(0,),
            num_features=top_k, num_samples=_NUM_SAMPLES)
        # Keep only words with a positive weight on the 'fake' class
        return [word for word, weight in exp.as_list(label=0) if weight > 0]
    except Exception as e:
        logger.warning("LIME explainer failed: %s", e)
        return []
```

*Caption: LIME explainability for fake verdicts. LIME perturbs the input (masking random words), re-runs the classifier on each variant, and identifies which words most increased the "fake" probability. The top words are returned to the app and highlighted, so a verdict is accompanied by a human-readable reason rather than an opaque score. Run only for English fake verdicts.*

**Report talking point:** this is your model-transparency contribution — the system shows *why* it flagged something, addressing the "black box" critique of ML classifiers.

---

## Listing 13 — Client-side defensive result parsing
**Source:** `frontend/newstrustai/lib/screens/result/result_parser.dart`
**Placement:** Frontend chapter.

```dart
// The backend can return fields in several shapes; normalise them into one
// view model so the UI never has to special-case the response.

double? _toDouble(dynamic v) => v == null
    ? null
    : (v is num ? v.toDouble() : double.tryParse(v.toString().trim()));

double _normScore(dynamic raw) {                 // accept a 0–1 or a 0–100 score
  final d = _toDouble(raw) ?? 0.0;
  return d <= 1.0 ? d * 100.0 : d.clamp(0.0, 100.0);
}

// Verdict label may arrive as real / verified / true / fake / false / mixed.
final bool isReal = label == "real" || label == "verified" || label == "true";
final bool isFake = label == "fake" || label == "false";

// Confidence is a 0–1 float on some backend paths; scale it to 0–100 so a
// genuine 0.95 renders as "95%", not "1%".
if (conf != null && conf <= 1.0) conf = conf * 100.0;
```

*Caption: Defensive parsing on the client. The API evolved to return confidences and scores on different scales (0–1 vs 0–100) and verdict labels under several names. The parser normalises all of these into a single view model, protecting the UI from inconsistent responses — for example scaling a 0–1 confidence to a percentage so a verified result is never mislabelled as low-confidence.*

**Report talking point:** shows the frontend is robust to backend variation — a real defect (95% shown as 1%) was fixed here, which you can cite as an example of integration testing paying off.

---

## Listing 14 — Trending freshness selection
**Source:** `backend/python_code/routes/trending.py` · `trending()`
**Placement:** News-feed feature section.

```python
@router.get("/trending")
def trending(request, limit: int = 10):
    wanted = max(1, min(limit, 100))
    items = [normalize_item(it) for it in safe_read_db() if isinstance(it, dict)]
    items.sort(key=lambda x: _pub_dt(x) or _EPOCH, reverse=True)     # freshest first

    # Prefer the last 3 days so renamed / dead feeds don't freeze the list;
    # fall back to the freshest overall if too few recent articles exist.
    cutoff = datetime.now(timezone.utc) - timedelta(days=3)
    recent = [it for it in items if (_pub_dt(it) or _EPOCH) >= cutoff]
    pool   = recent if len(recent) >= wanted else items

    # Order sources by their freshest article (active feeds lead), then
    # round-robin one-per-source for a list that is fresh AND diverse.
    buckets = {}
    for it in pool:
        buckets.setdefault((it.get("source") or "Unknown").strip(), []).append(it)
    sources = sorted(buckets, key=lambda s: _pub_dt(buckets[s][0]) or _EPOCH, reverse=True)

    out = []
    while len(out) < wanted and sources:
        for src in list(sources):
            if len(out) >= wanted: break
            if buckets[src]: out.append(buckets[src].pop(0))
            if not buckets[src]: sources.remove(src)

    for it in out:                                # attach a derived topic category
        it["category"] = _categorize(it.get("title", ""), it.get("summary", ""))
    return {"items": out}
```

*Caption: The trending-feed selection algorithm. Articles are sorted newest-first, filtered to a recency window (so renamed or inactive feeds cannot dominate with stale items), then bucketed by source and round-robined — with sources ordered by their freshest article — to produce a list that is both current and diverse across outlets. Each returned item is tagged with a derived topic category.*

**Report talking point:** a naive "latest N" feed froze on stale, renamed feeds; this recency-plus-diversity algorithm was the fix and demonstrates data-quality handling on a live, growing dataset.

---

*Generated as a companion to `SYSTEM_DOCUMENTATION.md` for the NewsTrustAI FYP report.*
