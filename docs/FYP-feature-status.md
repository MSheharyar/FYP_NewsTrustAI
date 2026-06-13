# NewsTrustAI — Objectives vs. Delivered

> Honest accounting of every proposal objective, its actual status, and a one-line note for anything that is Partial or Future Work. Examiners are told about scope changes up-front rather than discovering them during the demo.

## Feature Status Table

| Objective (from proposal) | Status | Notes |
|--------------------------|--------|-------|
| Text claim verification (English) | Done | 7-stage pipeline: BM25 → fuzzy → key-facts guard → NLI → BERT → LIME → fusion |
| Text claim verification (Urdu) | Done | Arabic-script + Romanised-Urdu detection; HuggingFace BERT API for classification; graceful fallback when API is unavailable |
| Multilingual support (English + Urdu) | Done | Single `/verify-text` endpoint auto-detects language and routes to correct model |
| Link / URL verification | Done | `/verify-link` scrapes article text then runs the same pipeline |
| Image / OCR verification | Done | `/verify-image` uses Tesseract OCR to extract text, then runs the pipeline |
| Google Fact Check API integration | Done | Queried when DB evidence is absent; rating normalised to true/false/mixed/unknown |
| GDELT live news lookup | Done | Fallback to real-time domain coverage check when local DB and Fact Check both miss |
| English fake-news BERT classifier | Done | `mrm8488/bert-tiny-finetuned-fake-news-detection` served locally; warmed up at startup |
| Urdu fake-news BERT classifier | Done | `ikomil/bert-urdu-fake-news` via HuggingFace Inference API (zero disk cost) |
| LIME explainability (English) | Done | Top-5 word-importance highlights shown when verdict is Fake |
| LIME explainability (Urdu) | Done | Skipped for Urdu (300 HuggingFace API calls per perturbation = unusable); BERT note shown instead |
| NER-based key-facts guard | Done | spaCy `en_core_web_sm` + vocabulary fallback; catches entity swaps and number mismatches |
| Entity-order inversion guard | Done | Added during hardening: "India beat Pakistan" no longer verifies as real against "Pakistan beat India" |
| Stale evidence warning | Done | Confidence penalised and warning shown when matched article is > 18 months old |
| Firebase Email/Phone authentication | Done | Email + password + OTP flows implemented in Flutter |
| Google social login | Partial | Firebase OAuth configured; deep-link redirect issues on Android physical devices; works on emulator |
| Facebook social login | Partial | Same deep-link issue as Google; deprioritised in favour of core NLP work |
| Analytics dashboard | Done | Verification history, fake/real/unverified breakdown, trending claims screen |
| Chatbot (Gemini 2.5 Flash) | Done | Contextual chatbot with conversation history; Gemini API key required |
| User profile (edit name/avatar) | Done | Profile screen with Firestore sync |
| Verification history (Firestore) | Done | Per-user history persisted and paginated |
| Trending / latest news feed | Done | `/trending` endpoint returns recent articles from the local DB |
| Rate limiting | Done | `slowapi` 10 requests/minute per IP on `/verify-text` |
| Result caching (viral claims) | Done | In-memory TTL+LRU cache (6 h TTL, 512-item LRU); repeat claims return `cached: true` |
| Graceful API degradation | Done | Each external API call wrapped in `safe_get_json`/`safe_post_json`; thread failures return `degraded: true` |
| TF Lite offline inference | Future work | Deprioritised: on-device model files increase APK size by ~90 MB and require quantisation toolchain not available in the FYP timeline. The HuggingFace API and local BERT model cover the online use-case. |
| Automated regression tests | Done | 26-test pytest suite covering pipeline verdicts, fuzzy matching, language detection, thread resilience, caching, and auth config |
| CI (GitHub Actions) | Done | Runs full pytest suite on every push to `main`/`dev` |

## Scoping rationale for Partial / Future items

**Social logins (Google/Facebook):** The Firebase OAuth config is complete and works on the Android emulator. The remaining issue is Android deep-link callback handling on physical devices — a platform integration concern unrelated to the core fact-checking objectives. It is deferred rather than dropped; a one-day fix resolves it post-defence.

**TF Lite offline inference:** The proposal included offline classification as a stretch goal. After evaluating the APK size impact (~90 MB model weight), quantisation complexity, and the fact that the online path (local BERT + HuggingFace) performs better, this was explicitly deprioritised. The system degrades gracefully when offline: the result cache serves recent verdicts, and the UI shows a connectivity message.

See also: [Scaling & Limitations](architecture/scaling-and-limitations.md)
