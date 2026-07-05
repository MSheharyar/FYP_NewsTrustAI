# NewsTrustAI — Complete System Documentation

**Project:** Final Year Project (FYP)  
**Author:** Muhammad Sheharyar Ghori  
**Purpose:** AI-powered fake news and misinformation detection system for Pakistan's news landscape  
**Languages Supported:** English and Urdu  

---

## Table of Contents

1. [What Is NewsTrustAI?](#1-what-is-newstrustai)
2. [System Architecture Overview](#2-system-architecture-overview)
3. [Technology Stack](#3-technology-stack)
4. [Backend Structure](#4-backend-structure)
5. [The Verification Pipeline — Step by Step](#5-the-verification-pipeline--step-by-step)
6. [Every Service Explained](#6-every-service-explained)
7. [The Database](#7-the-database)
8. [API Routes](#8-api-routes)
9. [Configuration and Environment Variables](#9-configuration-and-environment-variables)
10. [Authentication System](#10-authentication-system)
11. [Flutter Frontend](#11-flutter-frontend)
12. [Result Rendering Logic](#12-result-rendering-logic)
13. [Verdict States and Confidence Bands](#13-verdict-states-and-confidence-bands)
14. [How to Run the System](#14-how-to-run-the-system)
15. [All Optimizations Applied](#15-all-optimizations-applied)
16. [Deployment & Hosting Architecture](#16-deployment--hosting-architecture)
17. [Trending News & Category Classification](#17-trending-news--category-classification)
18. [Change Log — Stabilization & Feature Session](#18-change-log--stabilization--feature-session)

---

## 1. What Is NewsTrustAI?

NewsTrustAI is a mobile application (Flutter) connected to a Python/FastAPI backend that analyzes a piece of news text or a URL and tells the user whether the claim is:

- **Verified (Real)** — supported by credible evidence from trusted sources
- **Fake / Misleading** — contradicted by evidence or flagged by fact-checkers
- **Disputed / Mixed** — fact-checkers disagree with each other
- **Unverified** — insufficient evidence to reach a verdict

The system was built to combat misinformation in Pakistan where viral fake news spreads rapidly via WhatsApp and social media. It supports both **English** and **Urdu** text input.

---

## 2. System Architecture Overview

```
User (Flutter App)
       |
       | HTTPS POST /verify-text
       | Bearer <Firebase ID Token>
       v
FastAPI Backend (uvicorn)
       |
       |--- middleware/auth.py  →  Firebase token verification
       |
       v
routes/verify.py
       |
       |--- [PARALLEL via ThreadPoolExecutor]
       |        |
       |        |--- hybrid_decision(text)         → RapidFuzz DB search
       |        |                                     + Google Fact Check API
       |        |                                     + GDELT live lookup
       |        |
       |        |--- TextClaimVerifier.verify(text) → BM25 retrieval
       |                                              + Semantic re-ranking
       |                                              + NLI batch scoring
       |
       |--- _fuse_nli_with_hybrid()   → merge results using 4 priority rules
       |
       |--- bert_predict() / urdu_bert_predict()  → binary fake/real
       |
       |--- _fuse_bert_with_hybrid()  → incorporate BERT signal
       |
       |--- get_fake_highlights()     → LIME explainability (fake only, English only)
       |
       v
JSON response → Flutter parses → result_screen.dart renders verdict
```

---

## 3. Technology Stack

### Backend (Python)
| Component | Library/Tool | Purpose |
|-----------|-------------|---------|
| Web framework | FastAPI + uvicorn | HTTP API server |
| NLI model | cross-encoder/nli-MiniLM2-L6-H768 (HuggingFace) | Semantic entailment/contradiction detection |
| Sentence embedder | sentence-transformers/all-MiniLM-L6-v2 | Semantic similarity for re-ranking |
| English BERT | Local fine-tuned model in `/model/` | Binary fake/real classification |
| Urdu BERT | ikomil/bert-urdu-fake-news (HuggingFace Inference API) | Urdu fake/real classification |
| Fuzzy matching | RapidFuzz (token_set_ratio, token_sort_ratio) | Keyword + paraphrase matching |
| BM25 retrieval | rank-bm25 (BM25Okapi) | Fast keyword-ranked article retrieval |
| NER | spaCy en_core_web_sm | Named entity recognition (persons, places, orgs, dates) |
| Explainability | LIME (lime.lime_text) | Word importance highlights for fake verdicts |
| Rate limiting | slowapi | 10 requests/minute per IP on /verify-text |
| Auth | firebase-admin | Firebase ID token verification |
| External APIs | Google Fact Check API, GDELT API, Google Gemini API | Live lookups |
| CORS | FastAPI CORSMiddleware | Cross-origin requests from Flutter |

### Frontend (Flutter / Dart)
| Component | Purpose |
|-----------|---------|
| Flutter | Cross-platform mobile app (Android/iOS) |
| Firebase Auth | User login / ID token generation |
| http package | API calls to backend |
| Provider / ViewModel | State management for result screen |

---

## 4. Backend Structure

```
backend/
├── python_code/
│   ├── main.py                    # FastAPI app, startup warmup, middleware
│   ├── text_verifier.py           # NLI + semantic re-ranking (TextClaimVerifier class)
│   ├── config/
│   │   └── settings.py            # All thresholds, model names, env vars
│   ├── db/
│   │   └── reader.py              # JSON database reader, BM25 index, cache invalidation
│   ├── middleware/
│   │   └── auth.py                # Firebase token verification middleware
│   ├── routes/
│   │   ├── verify.py              # POST /verify-text — main verification endpoint
│   │   ├── links.py               # POST /verify-link — URL-based verification
│   │   ├── trending.py            # GET /trending — fresh news feed + topic category classifier
│   │   ├── debug.py               # Debug/admin endpoints
│   │   └── chat.py                # POST /chat — Gemini AI chatbot
│   ├── services/
│   │   ├── verification.py        # hybrid_decision() — core DB + factcheck + GDELT logic
│   │   ├── matching.py            # score_match() — RapidFuzz scoring with inversion guard
│   │   ├── facts.py               # NER + key_facts_guard() — entity extraction & validation
│   │   ├── factcheck.py           # Google Fact Check API client
│   │   ├── gdelt.py               # GDELT live news domain lookup
│   │   ├── bert.py                # English BERT inference (local model)
│   │   ├── urdu_bert.py           # Urdu BERT via HuggingFace API + Romanized Urdu detection
│   │   ├── entities.py            # Entity-level helpers
│   │   └── lime_explainer.py      # LIME word importance explainer
│   └── utils/
│       └── text.py                # clean_claim_text(), normalize_text()
├── global_news_db.json            # Flat-file DB of scraped news (~38,800+ and growing)
└── start_backend.ps1              # PowerShell startup script (sets REQUIRE_AUTH=false)
```

---

## 5. The Verification Pipeline — Step by Step

When a user submits text in the Flutter app and taps "Analyze", this is exactly what happens:

### Step 0: Request Entry
- Flutter sends `POST /verify-text` with JSON body `{"text": "...", "query": "..."}` and a Firebase ID token in the `Authorization: Bearer <token>` header.
- `middleware/auth.py` intercepts the request. If `REQUIRE_AUTH=true`, it verifies the token with Firebase Admin SDK. If invalid → 401 Unauthorized.

### Step 1: Language Detection
- `is_urdu(text)` in `services/urdu_bert.py` runs two checks:
  1. **Unicode block check**: counts how many characters fall in Arabic/Urdu Unicode ranges (U+0600–U+06FF, U+0750–U+077F). If ≥ 30% → Urdu.
  2. **Romanized Urdu check**: matches against a word-list of ~80 common Romanized Urdu words (`_ROMAN_URDU_WORDS`). If ≥ 3 hits → Urdu.
- If Urdu: NLI and LIME are **skipped** entirely (BM25 regex extracts nothing from Arabic script; LIME would make 100 HuggingFace API calls and timeout).

### Step 2: Parallel Execution (English only)
Using a module-level `ThreadPoolExecutor(max_workers=2)`:
- **Thread A**: `hybrid_decision(text)` — RapidFuzz database search + Google Fact Check + GDELT
- **Thread B**: `TextClaimVerifier.verify(text, db_search_fn)` — BM25 retrieval + semantic re-ranking + NLI scoring

Both run simultaneously. Wall-clock time = `max(t_hybrid, t_nli)` instead of `t_hybrid + t_nli`.

For **Urdu**: only `hybrid_decision(text)` runs (single thread, no executor needed).

### Step 3: Hybrid Decision (`hybrid_decision`)
This is the core RapidFuzz-based verification. See full details in Section 6.1.

The function:
1. Checks if input is too vague → returns `input_too_vague`
2. Retrieves candidates via BM25 keyword index (top-100)
3. Scores each with RapidFuzz `token_set_ratio` + `token_sort_ratio` (with inversion guard)
4. Checks strong matches (score ≥ 75) → runs `key_facts_guard` to detect edited claims
5. Checks soft matches (score 52–74) → returns `soft_db_match` or `edited_claim_suspected`
6. If no DB match → calls Google Fact Check API
7. If no fact-check → calls GDELT live lookup
8. Final fallback → `unverified`

### Step 4: NLI Fusion (`_fuse_nli_with_hybrid`)
After both threads complete, their results are merged using 4 priority rules:

| Rule | Condition | Action |
|------|-----------|--------|
| 1 | Hybrid method is authoritative (fact-check, GDELT, edited-claim, too-vague) | Hybrid wins, NLI debug attached |
| 2 | Hybrid = UNVERIFIED + NLI is decisive (verified=True) | NLI rescues the claim |
| 3a | Hybrid = REAL + NLI says FAKE with ≥ 85% confidence | NLI overrides → FAKE (semantic inversion) |
| 3b | Hybrid = REAL + NLI says FAKE with 75–84% confidence | Flag `model_disagreement`, keep hybrid |
| 4 | Hybrid = REAL + NLI confirms REAL | Boost confidence by +3%, flag `nli_confirmed` |
| 5 | All other cases | Hybrid wins, NLI debug attached |

### Step 5: BERT Classification
- **English**: `bert_predict(text)` — local PyTorch model in `/model/` folder, runs inference and returns `{"label": "fake"|"real", "confidence": float, "probabilities": {...}}`
- **Urdu**: `urdu_bert_predict(text)` — calls HuggingFace Inference API with `ikomil/bert-urdu-fake-news`

BERT result is fused into the hybrid result via `_fuse_bert_with_hybrid()`:
- If hybrid = `unverified` and BERT says fake (≥ 88%) → promote to `bert_only` fake verdict (confidence: 78%)
- If hybrid = `unverified` and BERT says real (≥ 90%) → add note but keep unverified
- If hybrid = `real` and BERT strongly says fake (≥ 92%) → flag `model_disagreement`

### Step 6: LIME Explainability (English, Fake verdicts only)
- Runs `LimeTextExplainer.explain_instance()` with 100 perturbation samples
- Creates 100 variants of the input text (random word masking) and calls BERT on each
- Identifies which words had the highest positive influence on the "fake" classification
- Returns top-5 words as `highlighted_words`
- Skipped for Urdu (would make 100 HuggingFace API calls) and for non-fake verdicts

### Step 7: Response
The final JSON response is returned to Flutter containing:
- `final_label`: "real" | "fake" | "unverified" | "mixed"
- `final_confidence`: 0–100 float
- `verification_method`: which path produced the verdict
- `matched_sources`: list of sources with URL, score, domain, trusted flag
- `bert_label`, `bert_confidence`: BERT's independent signal
- `highlighted_words`: LIME word importance (fake only)
- `detected_language`: "english" | "urdu"
- `stale_evidence`, `evidence_age_days`: staleness warnings
- `nli_confirmed`: true if NLI semantically confirmed a REAL verdict
- `model_disagreement`: true if BERT and evidence-based verdict conflict

---

## 6. Every Service Explained

### 6.1 `services/verification.py` — Hybrid Decision Engine

The main verification function `hybrid_decision(text)` does:

**Input vagueness check** (`looks_unstructured`, in `text_verifier.py`):
- Judged primarily by **word count**, not capitalisation. Counts "real" words (2+ letter tokens, Latin **or** Urdu/Arabic script).
- Rejected only when: fewer than 4 words AND under `MIN_TEXT_LEN` chars; OR 2+ emoji; OR more than 18 non-standard symbols; OR (no capitals AND no digits AND fewer than 5 words AND under 60 chars).
- **Why the rewrite:** the previous rule rejected *any* lowercase text under 120 chars, so normal news headlines (often 50–70 chars and/or lowercase) were bounced as `input_too_vague` before the database was even searched. Word-count is a far better "is this searchable" signal, and including the Urdu/Arabic range fixes short Urdu headlines that previously always failed.

**BM25 candidate retrieval**:
- Extracts 4+ letter keywords from the normalized claim using regex
- Runs the DB search when the claim has **≥ 2 named entities OR ≥ 4 distinct content keywords**. spaCy NER misses many valid entities (lowercase player surnames, foreign/sports terms), so a keyword-rich headline that skipped the entity gate previously returned `no_evidence` even though the matching article was in the DB. `VERIFY_THRESHOLD` still gates the actual matches, so precision is unchanged.
- Calls `get_candidate_articles(keywords, top_k=100)` which returns BM25-ranked articles
- Falls back to full DB scan if no keywords found

**Lazy NER caching**:
- `_claim_facts_cache = [None]` closure pattern
- spaCy NER runs only once per request regardless of how many guard calls happen
- `_get_claim_facts()` returns cached result on second call

**Scoring and matching**:
- For each candidate: scores `title + summary` and `title + summary + body`
- Takes `max(s1, s2)` as the article score
- `VERIFY_THRESHOLD = 75` → "strong match"
- `SOFT_MATCH_STRONG ≈ 63` → "soft strong match"
- `SOFT_MATCH_MIN ≈ 52` → "weak match"

**Staleness detection**:
- `_article_age_days(art)` parses `publishedAt` or `scrapedAt` ISO dates
- Articles older than 548 days (18 months) → `stale_evidence = True`, confidence −7

**Domain classification** (`_is_main_source_domain`):
- "Main" sources: arynews.tv, dawn.com, bbc.com, bbc.co.uk, cnn.com
- "Other major": reuters.com, apnews.com, aljazeera.com, theguardian.com, nytimes.com
- Domain set precomputed as `frozenset` at import time (no rebuilding per request)

**Confidence assignment**:
- 3+ main sources → 95% (CONF_HIGH)
- 1–2 main sources → 88% (CONF_SLIGHTLY_LOW)
- Other sources → 78% (CONF_LOW)
- GDELT other major → 65% (CONF_VERY_LOW)

### 6.2 `services/matching.py` — Fuzzy Scoring with Inversion Guard

```python
def score_match(query, text):
    tset  = fuzz.token_set_ratio(query, text)   # ignores word order
    tsort = fuzz.token_sort_ratio(query, text)  # sorts words before comparing
    base  = max(tset, tsort)
    
    # Inversion guard: "Pakistan beat India" vs "India beat Pakistan"
    # Both get token_set_ratio=100, but fuzz.ratio (character-level) < 55
    if base >= 85:
        raw = fuzz.ratio(query[:200], text[:200])
        if raw < 55:
            return int(0.65 * base + 0.35 * raw)  # penalize inversions
    return base
```

This prevents the system from verifying "India beat Pakistan" as real just because "Pakistan beat India" is in the database.

### 6.3 `services/facts.py` — Named Entity Extraction + Key Facts Guard

**`facts_from_text(text)`** extracts:
- **Persons**: spaCy PERSON entities + regex fallback
- **Locations**: spaCy GPE/LOC + regex from `_LOC_TERMS` (80+ terms)
- **Organizations**: spaCy ORG + regex from `_ORG_TERMS`
- **Dates**: spaCy DATE + month name regex
- **Numbers**: digit extraction + `"{n} {unit}"` pairs (e.g., "60 deaths", "60 seats")
- **Actions**: verb extraction from `_ACTION_TERMS` (60+ terms)

**`key_facts_guard(claim_text, evidence_text, claim_facts=None)`** checks if a claim's key facts are consistent with the matched evidence:
- Compares persons, locations, dates, numbers, orgs, actions between claim and evidence
- Uses a **majority rule** (≥ 50% of extracted groups must match) not all-or-nothing
- Returns `(True, debug)` if facts match → safe to verify
- Returns `(False, debug)` if facts mismatch → `edited_claim_suspected`

Example: "PM Khan visited Beijing" matched with "PM Modi visited Beijing" → persons don't match → edited claim detected.

### 6.4 `text_verifier.py` — NLI Semantic Verification

**`TextClaimVerifier` class** owns:
- `SentenceTransformer` for semantic embeddings
- `AutoModelForSequenceClassification` (NLI cross-encoder) for entailment scoring

**`verify(user_text, search_fn)`** pipeline:
1. Split input into sentences, build search queries (quoted, full, keyword)
2. Call `search_fn` (BM25-backed) for each query, deduplicate results by URL
3. **Semantic re-rank**: compute cosine similarity between claim embedding and each evidence text embedding; filter to `similarity ≥ 0.55`
4. **NLI batch scoring**: run all premises through NLI in one forward pass → `[(label, confidence), ...]`
5. **Vote aggregation**: weighted by `confidence × (0.7 + 0.3 × semantic_similarity)`; entailment wins only if `entail_ratio ≥ 55%`; small bonus +1.2% per extra supporting piece (cap +5%)
6. **Multi-sentence selection**: try up to 2 sentence candidates, pick the one with stronger decisive NLI signal

**Verdict logic**:
- ENTAILMENT ≥ 0.70 + entail dominant → REAL
- CONTRADICTION ≥ 0.70 + contra dominant → FAKE
- Otherwise → UNVERIFIED

### 6.5 `services/bert.py` — English BERT Classifier

- Loads fine-tuned model from `MODEL_DIR` (env-configurable, defaults to `../model/`)
- Cached at startup via `warmup_bert()`
- Returns `{"label": "fake"|"real", "confidence": float (0–1), "probabilities": {"fake": f, "real": r}}`
- If model files are missing or PyTorch unavailable → returns note `"BERT unavailable"`

### 6.6 `services/urdu_bert.py` — Urdu BERT + Language Detection

**`is_urdu(text)`**:
1. Count characters in Arabic/Urdu Unicode blocks (U+0600–U+06FF, U+0750–U+077F)
2. If ≥ 30% of characters → Urdu
3. Otherwise, run Romanized Urdu word-list check (80+ words like "nahi", "hai", "mein", "aur", "yeh")
4. If ≥ 3 matches → Urdu

**`urdu_bert_predict(text)`**:
- Calls HuggingFace Inference API with model `ikomil/bert-urdu-fake-news`
- Requires `HF_API_TOKEN` env var
- Returns same format as `bert_predict()`

### 6.7 `services/factcheck.py` — Google Fact Check API

- Queries `https://factchecktools.googleapis.com/v1alpha1/claims:search`
- Requires `GOOGLE_FACTCHECK_API_KEY` env var
- Timeout: 5 seconds
- `_rating_bucket(rating)` normalizes text ratings: "Pants on Fire" → "false", "Mostly True" → "mixed", etc.
- Returns up to 5 fact-check results as sources for the response

### 6.8 `services/gdelt.py` — GDELT Live News Lookup

- Queries GDELT API for recent news articles mentioning the claim
- Classifies results by domain: "main" (arynews, dawn, bbc, cnn) vs "other major" (reuters, apnews, etc.)
- Only called when DB and fact-check both return nothing AND the claim has named entities
- `found_main` → verified via main sources; `found_other` → verified via other major sources

### 6.9 `services/lime_explainer.py` — LIME Explainability

- Uses `LimeTextExplainer(class_names=['fake', 'real'])`
- `_NUM_SAMPLES = 100` (configurable via `LIME_NUM_SAMPLES` env var)
- Creates 100 random text perturbations (word masking) and measures which removals most reduce the "fake" class probability
- Returns top-K words with positive fake-direction weight
- Only called for English fake verdicts

### 6.10 `db/reader.py` — Database Reader with BM25

- Reads `global_news_db.json` (~38,800+ articles, auto-refreshed every 30 min from 26 RSS feeds, capped at 120,000)
- **BM25 index**: built from `rank-bm25.BM25Okapi` on article title + summary tokens
- `get_candidate_articles(keywords, top_k=100)` → BM25-ranked top results for given keywords
- **Cache invalidation**: tracks file `mtime` (`os.path.getmtime`) and auto-reloads if DB file changes while server is live
- **Keyword index**: secondary inverted index for fast pre-filtering before BM25

---

## 7. The Database

**File**: `backend/global_news_db.json`  
**Size**: ~38,800+ articles and growing (a background fetcher pulls from **26 RSS feeds** every 30 minutes; the file is capped at 120,000 articles, oldest-first eviction)  
**Format**: JSON array of article objects  

Each article has:
```json
{
  "title": "...",
  "summary": "...",
  "body": "...",
  "url": "https://...",
  "source": "Dawn",
  "sourceName": "Dawn",
  "domain": "dawn.com",
  "publishedAt": "2024-03-15T10:30:00Z",
  "scrapedAt": "2024-03-15T11:00:00Z"
}
```

The database is a flat JSON file — no SQL or NoSQL database server. It is loaded into memory at startup and indexed with BM25. Updates are detected via file modification time.

---

## 8. API Routes

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/verify-text` | Required | Main text verification endpoint |
| POST | `/verify-link` | Required | URL-based news verification |
| GET | `/trending?limit=N` | Required | Trending / all-news feed (freshest first, deduped by source). `limit` default 10, max 100. Each item carries a derived `category`. |
| POST | `/chat` | Required | Gemini AI chatbot for news questions |
| GET | `/debug/*` | Optional | Debug endpoints for development |

### POST `/verify-text`
**Request body**:
```json
{
  "text": "The news claim to verify",
  "query": "optional override search query"
}
```

**Response** (main fields):
```json
{
  "final_label": "real | fake | unverified | mixed",
  "final_confidence": 88.0,
  "verification_method": "db_match | soft_db_match | google_factcheck | gdelt_main_sources | bert_only | ...",
  "source_tier": "main | other | unknown",
  "final_reason": "Human-readable explanation",
  "matched_sources": [...],
  "bert_label": "real | fake",
  "bert_confidence": 0.92,
  "highlighted_words": ["word1", "word2"],
  "detected_language": "english | urdu",
  "stale_evidence": false,
  "evidence_age_days": null,
  "nli_confirmed": false,
  "model_disagreement": false,
  "query_used": "the claim text used for search"
}
```

**Rate limit**: 10 requests per minute per IP address.  
**Errors**: 400 (bad input), 401 (unauthorized), 422 (validation error), 429 (rate limited), 500 (server error).

---

## 9. Configuration and Environment Variables

All config is in `config/settings.py`. Every value can be overridden via environment variable.

| Variable | Default | Purpose |
|----------|---------|---------|
| `DATABASE_FILE` | `../global_news_db.json` | Path to the news article database |
| `MODEL_DIR` | `../model` | Path to local English BERT model files |
| `LOG_LEVEL` | `INFO` | Python logging level |
| `VERIFY_THRESHOLD` | `75` | Minimum RapidFuzz score to count as "strong match" |
| `ENTITY_OVERLAP_MIN` | `0.34` | Minimum entity overlap ratio for key facts guard |
| `CONF_HIGH` | `95.0` | Confidence for 3+ main source matches |
| `CONF_SLIGHTLY_LOW` | `88.0` | Confidence for 1–2 main source matches |
| `CONF_LOW` | `78.0` | Confidence for other-source matches / BERT-only |
| `CONF_VERY_LOW` | `65.0` | Confidence for GDELT other major source matches |
| `MIN_TEXT_LEN` | `35` | Minimum characters before input is considered valid |
| `BERT_SUSPECT_FAKE_THRESHOLD` | `0.88` | BERT confidence to promote unverified → fake |
| `BERT_SUGGEST_REAL_THRESHOLD` | `0.90` | BERT confidence to add real suggestion note |
| `BERT_DISAGREEMENT_THRESHOLD` | `0.92` | BERT confidence to flag model disagreement |
| `NLI_MIN_SEMANTIC` | `0.55` | Minimum cosine similarity for NLI evidence selection |
| `NLI_ENTAIL_THRESHOLD` | `0.70` | Minimum NLI confidence to declare entailment |
| `NLI_MODEL_NAME` | `cross-encoder/nli-MiniLM2-L6-H768` | HuggingFace NLI model |
| `EMBED_MODEL_NAME` | `sentence-transformers/all-MiniLM-L6-v2` | Sentence embedding model |
| `CORS_ORIGINS` | `*` | Comma-separated allowed CORS origins |
| `GOOGLE_FACTCHECK_API_KEY` | `""` | Google Fact Check Tools API key |
| `GEMINI_API_KEY` | `""` | Google Gemini API key for chatbot |
| `HF_API_TOKEN` | `""` | HuggingFace API token for Urdu model |
| `URDU_MODEL_ID` | `ikomil/bert-urdu-fake-news` | HuggingFace model ID for Urdu |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | `""` | Firebase service account JSON string |
| `REQUIRE_AUTH` | `true` | Set to `false` to bypass Firebase auth (local dev) |
| `LIME_NUM_SAMPLES` | `100` | Number of LIME perturbation samples |

---

## 10. Authentication System

**Firebase Authentication** is used for user management.

**Frontend (Flutter)**:
- Users log in with email/password via Firebase Auth SDK
- `FirebaseAuth.instance.currentUser?.getIdToken()` gets a short-lived JWT token
- Every API request includes: `Authorization: Bearer <id_token>`

**Backend (FastAPI)**:
- `middleware/auth.py` has a `require_firebase_auth` dependency
- If `REQUIRE_AUTH=false` → returns a dummy user dict (local development bypass)
- If `REQUIRE_AUTH=true` → calls `firebase_admin.auth.verify_id_token(token)` which:
  1. Validates the JWT signature against Google's public keys
  2. Checks expiry
  3. Returns the decoded user dict (uid, email, etc.)
- If token is missing or invalid → raises HTTP 401

**Firebase Admin SDK initialization** (`main.py`):
- If `FIREBASE_SERVICE_ACCOUNT_JSON` is set → loads service account from the JSON string
- Otherwise → uses Application Default Credentials (ADC via `GOOGLE_APPLICATION_CREDENTIALS` env var)
- If init fails → logs a warning; token verification will be skipped if `REQUIRE_AUTH=false`

---

## 11. Flutter Frontend

**Location**: `frontend/newstrustai/lib/`

**Key screens**:

| Screen | File | Purpose |
|--------|------|---------|
| Splash | `screens/splash_screen.dart` | Loading + auth check |
| Login | `screens/login_screen.dart` | Firebase email/password login |
| Sign Up | `screens/signup_screen.dart` | New user registration |
| Home | `screens/home/home_screen.dart` | Dashboard with quick actions |
| Verify Text | Part of home | Input text to verify |
| Verify Link | `screens/verify_link_screen.dart` | Enter news URL |
| Result | `screens/result/result_screen.dart` | Full verification result display + thumbs up/down feedback |
| All News | `screens/allnews_screen.dart` | News feed with **topic-category filter pills** (All, Politics, Business, Sports, World, Technology, Entertainment, Health, General), pull-to-refresh, fetches 60 articles |
| Analytics | `screens/analytics_screen.dart` | User verification history stats |
| History | `screens/history_screen.dart` | Past verifications |
| Chatbot | `screens/chatbot_screen.dart` | Gemini AI chat |
| Profile | `screens/profile_screen.dart` | User account |
| Upload Image | `screens/upload_image_screen.dart` | Image-based news (OCR) |

**API communication** (`lib/services/api_service.dart`):
```dart
static Future<Map<String, String>> _authHeaders() async {
  final user = FirebaseAuth.instance.currentUser;
  final token = await user?.getIdToken();
  return {
    "Content-Type": "application/json",
    // Bypass ngrok's free-tier browser interstitial so JSON is returned directly
    "ngrok-skip-browser-warning": "true",
    if (token != null) "Authorization": "Bearer $token",
  };
}
```

Every `POST` and `GET` request uses `_authHeaders()` to attach the Firebase token. The token fetch is also wrapped in its own timeout so a slow Firebase refresh cannot hang a request indefinitely.

---

## 12. Result Rendering Logic

The result screen has three files that work together:

### `result_view_model.dart`
Plain data class (ViewModel) holding all fields needed by the UI:
- Verdict: `verdictTitle`, `verdgetSubtitle`, `badgeText`, `confidence`
- State booleans: `isReal`, `isFake`, `isMixed`, `isUnverified`
- Explanation: `reasonText`, `whatCheckedText`, `tips`
- Sources: `List<SourceMatchVM>` with `source`, `domain`, `url`, `score`, `trusted`, `type`, `rating`
- Debug: `bertLabel`, `bertConfidence`, `modelDisagreement`, `factsDebug`
- Quality signals: `staleEvidence`, `evidenceAgeDays`, `nliConfirmed`, `bertNote`
- Language: `detectedLanguage`

### `result_parser.dart`
Converts raw JSON from the API into a `ResultViewModel`. Handles:
- Multiple possible field names (`matched_sources` / `top_matches` / `sources`)
- Score normalization (0–1 or 0–100 both accepted)
- Label normalization ("verified" → "real", "true" → "real")
- `_inferType()` for source type ("factcheck" / "db" / "live")
- Building human-readable `whatCheckedText` based on `verification_method`
- `method == "edited_claim_suspected"` → forces `isUnverified` UI state

### `result_screen.dart`
Renders the verdict UI with:
- Color-coded verdict card: green (real), red (fake), purple (mixed), orange (unverified)
- Confidence percentage display
- Matched sources list with domain chips, trust badges, ratings
- BERT model result card
- Stale evidence amber warning card
- NLI-confirmed teal badge
- BERT note grey info card
- "Why this result?" expandable explanation
- "What was checked?" process description
- Verification tips

---

## 13. Verdict States and Confidence Bands

### Verdict Labels
| `final_label` | Displayed as | Color | Meaning |
|---------------|-------------|-------|---------|
| `real` | "Verified" | Green | Strong supporting evidence found |
| `fake` | "Fake / Misleading" | Red | Contradicted by evidence or fact-checkers |
| `mixed` | "Disputed / Mixed Signals" | Purple | Fact-checkers disagree |
| `unverified` | "Unverified (Insufficient Evidence)" | Orange | Could not confirm or deny |

### Verification Methods
| Method | Trigger |
|--------|---------|
| `db_match` | Strong fuzzy match (≥ 75) in article database |
| `soft_db_match` | Paraphrase-tolerant match (63–74) |
| `weak_similar_coverage` | Low-score match (52–63), not strong enough to verify |
| `edited_claim_suspected` | Match found but key facts (persons/places/numbers) don't align |
| `input_too_vague` | Text is too short, vague, or lacks named entities |
| `google_factcheck` | Google Fact Check API returned a result |
| `gdelt_main_sources` | GDELT live lookup found coverage on main news domains |
| `gdelt_other_major_sources` | GDELT found coverage on other major domains |
| `nli_semantic` | NLI rescued an unverified claim with strong entailment |
| `nli_contradiction` | NLI overrode a REAL verdict with strong contradiction (≥ 85%) |
| `bert_only` | No external evidence; BERT model suspects fake (≥ 88%) |
| `bert_suggested_real` | No external evidence; BERT model suggests real (≥ 90%) |
| `no_evidence` | No evidence at all; claim has no extractable entities |

### Confidence Bands
| Value | Meaning |
|-------|---------|
| 95% | Corroborated by 3+ main sources |
| 88% | Corroborated by 1–2 main sources |
| 78% | Corroborated by other sources / BERT-only fake |
| 65% | GDELT other major sources |
| −7% | Penalty for stale evidence (> 18 months old) |

---

## 14. How to Run the System

### Start the Backend (Local Development)

```powershell
# From the repo root:
.\backend\start_backend.ps1
```

This script sets `REQUIRE_AUTH=false` (bypasses Firebase token check) and starts uvicorn:
```powershell
$env:REQUIRE_AUTH = "false"
Set-Location "$PSScriptRoot\python_code"
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

**Required environment variables** (set before running, or in a `.env` file):
```
GOOGLE_FACTCHECK_API_KEY=your_key
GEMINI_API_KEY=your_key
HF_API_TOKEN=your_huggingface_token
```

### Startup Warmup Sequence
On first start, `main.py` warms up all heavy models:
1. `warmup_bert()` — loads English BERT model into memory
2. `warmup_text_verifier()` — loads NLI model and sentence embedder
3. `get_candidate_articles(["news"])` — builds BM25 index from the JSON database
4. `facts_from_text("test warmup")` — initializes spaCy NER pipeline

**First request** after a cold start will be fast because all models are pre-loaded.

### Run the Flutter App
```bash
cd frontend/newstrustai
flutter run
```

Make sure `lib/services/api_service.dart` points to the correct backend URL (e.g., `http://10.0.2.2:8000` for Android emulator, or your machine's IP for a physical device).

### Production Deployment
- Set `REQUIRE_AUTH=true` (default)
- Set `FIREBASE_SERVICE_ACCOUNT_JSON` to your Firebase service account JSON string
- Set all API keys as environment variables
- Run without `--reload` flag

The live FYP deployment runs on a Hostinger VPS behind **nginx + an ngrok tunnel**, all as systemd services. See **[Section 16 — Deployment & Hosting Architecture](#16-deployment--hosting-architecture)** for the full network path and the reason a tunnel is used instead of the raw IP.

---

## 15. All Optimizations Applied

Over three development sessions, 25 improvements were made:

| # | What Changed | File | Why |
|---|-------------|------|-----|
| 1 | NLI batch scoring + vote aggregation | `text_verifier.py` | One forward pass instead of N individual NLI calls |
| 2 | LIME sample count configurable | `lime_explainer.py` | 100 samples default (was 300), env-overridable |
| 3 | Expanded NER term lists | `services/facts.py` | 60+ actions, 80+ locations, title-word filter |
| 4 | BM25 retrieval | `db/reader.py` | Replaced boolean keyword filter with ranked retrieval |
| 5 | spaCy NER hybrid | `services/facts.py` | spaCy entities unioned with regex fallback |
| 6 | Configurable model names | `config/settings.py` | NLI and embedding models via env var |
| 7 | BM25 wired into NLI path | `routes/verify.py` | NLI search uses BM25 not full DB scan |
| 8 | LIME replaces SHAP | `routes/verify.py` | SHAP too slow; LIME is text-native |
| 9 | Stale article detection | `services/verification.py` | Evidence > 18 months → −7% confidence + warning |
| 10 | Parallel NLI + hybrid | `routes/verify.py` | Both run simultaneously, fused by priority rules |
| 11 | NLI override threshold | `routes/verify.py` | ≥ 85% NLI overrides REAL; 75–85% flags disagreement |
| 12 | Gemini key via env var | `config/settings.py` | Removed hardcoded key |
| 13 | LIME skipped for Urdu | `routes/verify.py` | 100 HuggingFace API calls → timeout |
| 14 | NLI skipped for Urdu | `routes/verify.py` | BM25 regex extracts nothing from Arabic script |
| 15 | Module-level ThreadPoolExecutor | `routes/verify.py` | Avoid spinning up 2 threads per request |
| 16 | BM25 + spaCy warmup at startup | `main.py` | Eliminate cold-start latency on first request |
| 17 | GDELT entity guard fixed | `services/verification.py` | Was backward; now skips only entity-free claims |
| 18 | DB cache mtime invalidation | `db/reader.py` | Auto-reloads if JSON file changes while server is live |
| 19 | Rate limiting | `routes/verify.py` | `slowapi` 10 req/min per IP |
| 20 | Multi-sentence NLI selection | `text_verifier.py` | Tries 2 sentence candidates; picks stronger NLI signal |
| 21 | Number + unit context | `services/facts.py` | "60 deaths" vs "60 seats" now distinguishable |
| 22 | Romanized Urdu detection | `services/urdu_bert.py` | Catches "yeh baat nahi hai" style Urdu |
| 23 | Stale evidence badge | `result_screen.dart` | Amber warning when evidence > 18 months |
| 24 | NLI confirmed badge | `result_screen.dart` | Teal "Semantically verified" card |
| 25 | BERT note surfaced | `result_screen.dart` | Grey info card when BERT unavailable |
| 26 | Inversion guard in fuzzy match | `services/matching.py` | "A beat B" vs "B beat A" now scored differently |
| 27 | Lazy NER caching | `services/verification.py` | spaCy runs once per request, not twice |
| 28 | Main domain set precomputed | `services/verification.py` | frozenset built once at import, not per article |
| 29 | Action guard changed to majority | `services/facts.py` | Require ≥ 50% group match, not all groups |
| 30 | Mixed verdict state | `result_parser.dart` + `result_screen.dart` | Purple UI state for fact-checker disagreements |

> A later stabilization & feature session added further fixes (deployment, verification-gate tuning, trending freshness, category pills, auth). These are documented in **[Section 18](#18-change-log--stabilization--feature-session)**.

---

## 16. Deployment & Hosting Architecture

The backend runs on a **Hostinger KVM VPS** (Ubuntu 24.04, 1 vCPU, 4 GB RAM) and the Flutter app reaches it over the public internet. The network path is deliberately **outbound-only** because the hosting provider drops all *inbound* TCP to the VPS.

```
Flutter app (Pixel / device)
      |  HTTPS
      v
https://<name>.ngrok-free.dev        ← stable public URL (ngrok edge)
      |  (ngrok agent holds an OUTBOUND tunnel from the VPS)
      v
ngrok agent  ──►  nginx  :80  ──►  uvicorn  :8000  (FastAPI backend)
                (reverse proxy)      (newstrustai.service, systemd)
```

**Why a tunnel instead of the raw IP?**
During testing, all inbound TCP to the VPS's public IP started being dropped at the provider's network edge (confirmed with `tcpdump` showing **0** inbound SYN packets while the server itself was healthy — `nginx`/`uvicorn` bound to `0.0.0.0`, empty `iptables`, IP on `eth0`). No firewall/port change fixed it because the drop is upstream. The fix routes traffic through an **outbound** ngrok tunnel (outbound connections work fine), giving a stable public HTTPS URL that is independent of the provider's broken inbound path.

**Components (all systemd services, auto-start on boot):**

| Service | Role | Notes |
|---------|------|-------|
| `newstrustai.service` | uvicorn running `main:app` on `127.0.0.1:8000` | The FastAPI backend |
| `nginx` | Reverse proxy `:80` → `127.0.0.1:8000` | Config in `/etc/nginx/sites-available/newstrustai` |
| `ngrok.service` | Outbound tunnel: free static domain → `http://localhost:80` | Config `/etc/ngrok.yml`, binary `/usr/local/bin/ngrok` |

**App-side configuration** (`lib/services/api_service.dart`):
- Default backend URL is the ngrok domain, baked in via `String.fromEnvironment('API_BASE_URL', defaultValue: 'https://<name>.ngrok-free.dev')` — works in **both** debug and release builds.
- All requests send an `ngrok-skip-browser-warning: true` header so ngrok returns the raw JSON instead of its free-tier interstitial page.
- Override at build time with `flutter run --dart-define=API_BASE_URL=https://...`.

**Deploying a backend change:** push to GitHub, then on the VPS:
```bash
cd /root/newstrustai/backend/python_code
git pull origin main && systemctl restart newstrustai
```

---

## 17. Trending News & Category Classification

### 17.1 Freshness selection (`routes/trending.py`)

`GET /trending?limit=N` builds the feed as follows:
1. Read all articles, sort **freshest-first** by parsed `publishedAt` (falling back to `scrapedAt`; undated articles sink to the bottom).
2. Keep only articles from the **last 3 days** (fall back to the freshest overall if fewer than `N` recent ones exist).
3. Bucket by `source`, **order the sources by their freshest article** (not alphabetically), then round-robin one article per source for a list that is both fresh and diverse.

**Why:** RSS feeds were renamed over time (e.g. `ARY` → `ARY News`, `ALJAZEERA` → `Al Jazeera`). The old names still held month-old articles in the DB, and the previous round-robin gave every source an equal slot **alphabetically**, so the dead old-named buckets always filled ~half the list with the same stale articles — the feed looked frozen even though the fetcher kept adding fresh news. Recency filtering + freshness-ordered sources make active feeds lead and dead feeds fall away.

### 17.2 Topic category classifier

The RSS data has **no category field**, so a topic is *derived* from each article's title + summary by `_categorize()`:
- A keyword dictionary maps 7 topics — **Sports, Business, Technology, Entertainment, Health, Politics, World** — to keyword lists (English **and** a set of Urdu keywords). Stems are used so word variants match (`politic` → politics/political, `palestin` → palestine/palestinians), along with notable named entities (Trump, Biden, congress).
- Each topic is scored by how many of its keywords appear in the text; the highest-scoring topic wins, else **General**.
- Only the **final selected slice** (≤ `limit` articles) is classified — the whole DB is never scanned.
- The chosen topic is attached as a `category` field on each returned article.

**Accuracy note:** because categories are keyword-derived rather than model-predicted, expect roughly 85–90% correct on entity-rich English headlines; very short or Urdu-only headlines may land in **General**. This is an explicit trade-off of deriving categories from data that has none.

### 17.3 Frontend (`screens/allnews_screen.dart`)

A stateful screen that fetches 60 categorised articles (`ApiService.fetchNews(limit: 60)`), shows a horizontal row of **filter pills**, and filters the list to the selected topic. Includes a per-card category chip, pull-to-refresh, and a per-category empty state.

---

## 18. Change Log — Stabilization & Feature Session

Fixes and features from the device-testing / stabilization session, in addition to the 30 optimizations in Section 15.

| # | Area | What Changed | File(s) | Why |
|---|------|-------------|---------|-----|
| 31 | Hosting | Backend served via permanent **ngrok tunnel + nginx** reverse proxy as systemd services | VPS config, `api_service.dart` | Provider dropped all inbound TCP; outbound tunnel restores a stable public HTTPS URL (see Section 16) |
| 32 | Result UI | **Confidence scaling fix** — `final_confidence` (0–1 float) scaled to 0–100 | `result_parser.dart` | A genuine 95% "Verified" result was rendering as "1% — Likely Fake/Unverified" |
| 33 | Data cleanup | **`stripHtml()`** applied to RSS summaries and Verify-Text trending examples | `utils/app_utils.dart`, `allnews_screen.dart`, `verify_text_screen.dart` | Raw markup like `<img src=...>` was showing as literal text |
| 34 | Verification | **`looks_unstructured` rewritten** to judge by word count (Latin/Urdu), not capital letters | `text_verifier.py` | Short/lowercase but complete headlines were rejected as `input_too_vague` before searching |
| 35 | Verification | DB search now runs for **keyword-rich claims** (≥ 4 distinct keywords), not only ≥ 2 NER entities | `services/verification.py` | Real headlines returned `no_evidence` even though the article was in the DB |
| 36 | Trending | Recency filter + **freshness-ordered** source round-robin | `routes/trending.py` | Renamed/dead feeds froze the feed with stale articles |
| 37 | Trending | `?limit=` query param (default 10, max 100) | `routes/trending.py` | Lets the All News screen pull a fuller batch |
| 38 | Feature | **Topic category classifier** + `category` field on each article | `routes/trending.py` | Powers the All News category pills (see Section 17) |
| 39 | Feature | **Category filter pills** on the All News screen (stateful, pull-to-refresh) | `allnews_screen.dart`, `api_service.dart` | Browse news by topic |
| 40 | Reliability | Trending loaders hardened with timeouts + `finally` guards; `_authHeaders()` bounded by its own timeout | `verify_text_screen.dart`, `home_tab.dart`, `api_service.dart` | A slow Firebase token refresh could leave the trending spinner stuck forever |
| 41 | Auth | **Google Sign-In fixed**: removed the wrong `clientId` (Android reads it from `google-services.json`), added a cancelled-sign-in null guard | `services/auth_service.dart` | `clientId` was for web/iOS; it broke the Android flow |
| 42 | Auth | **`applicationId` aligned** with the Firebase package (`com.example.fyp_proj`) and debug SHA-1/SHA-256 registered | `android/app/build.gradle.kts` + Firebase console | Package mismatch caused Google Sign-In `DEVELOPER_ERROR` |
| 43 | UX | Facebook button now shows an informational message instead of attempting a broken login | `login_screen.dart` | Facebook app was not configured |
| 44 | Feature | **Thumbs up/down feedback** on the result screen, saved to Firestore `users/{uid}/feedback` | `result_screen.dart`, `firestore_history_service.dart` | Collects user feedback for future active-learning |
| 45 | News cards | Source-coloured gradient fallback header when an article has no image | `news_card.dart`, `allnews_screen.dart` | Most RSS items lack images; grey placeholder looked broken |
| 46 | CI | Removed invalid `--cov-omit` pytest flag; widened `numpy` pin | `.github/workflows/backend-ci.yml`, `requirements.txt` | CI was failing on every run |

---

*This document was generated to provide a complete reference for the NewsTrustAI FYP system.*
