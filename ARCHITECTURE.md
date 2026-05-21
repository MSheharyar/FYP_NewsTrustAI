# NewsTrustAI — System Architecture

```mermaid
flowchart TD
    USER([User])

    %% ── FRONTEND ─────────────────────────────────────────────
    subgraph FL ["📱 Flutter Frontend"]
        direction TB

        subgraph ENTRY ["App Entry"]
            SP[Splash Screen] --> OB[Onboarding\n3-slide PageView]
            OB --> LG[Login / Signup]
        end

        subgraph SCREENS ["Main Screens  —  Bottom Nav"]
            direction LR
            HOME[Home Tab\nStats · Trending · Quick Actions]
            ASCREEN[Analytics]
            HIST[History]
            CBOT[Chatbot Screen]
            PROF[Profile]
        end

        subgraph INPUT ["Verification Entry Points"]
            VT[Verify Text\nPaste / type claim]
            VL[Verify Link\nPaste URL]
            OCR[Upload Image\nML Kit OCR → extracted text]
        end

        OV[Animated Loading Overlay\nPreprocessing → Search → AI → Verdict]
        RS[Result Screen\nRadial Confidence Gauge · Verdict · Share\nExplainability · Matched Sources]

        LG --> SCREENS
        HOME --> INPUT
        INPUT --> OV --> RS
    end

    %% ── BACKEND ─────────────────────────────────────────────
    subgraph BE ["⚙️ FastAPI Backend  —  Python 3.11"]
        direction TB

        subgraph ROUTES ["API Routes"]
            R1["POST /verify-text"]
            R2["POST /verify-link"]
            R3["POST /chat"]
            R4["GET /trending  /  GET /allnews"]
        end

        subgraph SCRAPE ["Link Scraper"]
            SC[BeautifulSoup\nFetch + parse article HTML]
        end

        subgraph VP ["🔍 Verification Pipeline"]
            direction TB
            LD[Language Detection\nis_urdu]

            LD --> ENG{English?}

            ENG -- Yes --> PARL[Run in Parallel]

            PARL --> HYB
            PARL --> NLI

            subgraph HYB ["Hybrid Decision"]
                direction TB
                BM25S[BM25 Candidate Retrieval]
                BM25S --> FUZZ[RapidFuzz Scoring\ntoken_set + token_sort + inversion guard]
                FUZZ --> SFMATCH{score >= 75?}
                SFMATCH -- Yes --> KFGUARD[Key Facts Guard\nspaCy NER entity check]
                KFGUARD --> HVERDICT[DB Verdict]
                SFMATCH -- No --> SOFTM[Soft Paraphrase Match\n42-74]
                SOFTM --> FACAPI[Google Fact Check API]
                FACAPI --> GDELT[GDELT Live Lookup\nEntity-based live news coverage]
                GDELT --> HVERDICT
            end

            subgraph NLI ["NLI Verifier"]
                direction TB
                QUES{Is a question?}
                QUES -- Yes --> SKIPNLI[Skip — questions\nare not falsifiable]
                QUES -- No --> SEMR[Sentence-BERT Rerank\nall-MiniLM-L6-v2]
                SEMR --> NLIMOD[NLI Model\ncross-encoder/nli-MiniLM2-L6-H768\nEntailment · Contradiction · Neutral]
                NLIMOD --> NLIVERDICT[NLI Verdict]
            end

            HVERDICT --> FUSE[Fuse NLI + Hybrid\nfact-check wins · NLI rescues unverified\nNLI overrides REAL if conf >= 0.85]
            NLIVERDICT --> FUSE
            SKIPNLI --> FUSE

            FUSE --> BERTM[BERT Classifier\nmrm8488/bert-tiny-finetuned-fake-news]
            BERTM --> LIMEE[LIME Explainer\nTop-5 word highlights for fake claims]
            LIMEE --> VERDICT["Final Verdict\n✅ Real  |  ❌ Fake / Misleading  |  ❓ Unverified"]

            ENG -- No / Urdu --> URDU[Urdu BERT\nikomil/bert-urdu-fake-news\nHuggingFace Inference API]
            URDU --> VERDICT
        end

        subgraph CP ["💬 Chat Pipeline"]
            direction TB
            RAGS[RAG DB Search\nBM25 top-5 relevant articles]
            RAGS --> GEMINI[Gemini 2.5 Flash\nSystem Prompt + DB Articles\n+ Verification Context + User Message]
            GEMINI --> REPLY[AI Reply]
        end

        subgraph DB ["🗄️ Local Database"]
            DBJSON[(global_news_db.json\n36000+ articles\nBBC · CNN · ARY · Dawn · Al Jazeera\n+ other sources)]
            BM25I[BM25Okapi Index\nin-memory at startup]
        end
    end

    %% ── EXTERNAL SERVICES ───────────────────────────────────
    subgraph EXT ["☁️ External Services"]
        FBA[Firebase Auth + Firestore\nAccounts · History · Analytics]
        GFC[Google Fact Check API]
        GDELTAPI[GDELT Project\nLive global news index]
        GAIAPI[Gemini API — Google AI Studio]
        HFAPI[HuggingFace Inference API\nUrdu model]
    end

    %% ── CONNECTIONS ─────────────────────────────────────────
    USER --> FL

    VT -->|text| R1
    VL -->|url| R2
    OCR -->|extracted text| R1
    CBOT -->|message + history + context| R3
    HOME -->|fetch feed| R4

    R2 --> SC -->|article text + domain| VP
    R1 --> VP
    R3 --> CP

    BM25S --> DBJSON
    SEMR --> DBJSON
    RAGS --> DBJSON
    BM25I -.->|indexed| DBJSON

    LG --> FBA
    HIST --> FBA
    ASCREEN --> FBA

    FACAPI --> GFC
    GDELT --> GDELTAPI
    GEMINI --> GAIAPI
    URDU --> HFAPI
```

---

## Verdict Decision Logic

| Condition | Verdict |
|---|---|
| DB score ≥ 75 + entity facts match | **Real** (78–95% confidence) |
| DB score ≥ 75 but entity facts mismatch | **Edited Claim Suspected** |
| Soft paraphrase match (42–74) | **Real** (lower confidence) |
| Google Fact Check says false | **Fake** (95% confidence) |
| NLI contradiction confidence ≥ 0.85 | **Fake / Misleading** |
| GDELT finds main source coverage | **Real** |
| Nothing found anywhere | **Unverified** |

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile App | Flutter 3 (Dart) |
| Backend API | FastAPI + Uvicorn (Python 3.11) |
| Auth & Storage | Firebase Auth + Cloud Firestore |
| Article Database | JSON flat-file, 36 000+ articles |
| Candidate Retrieval | BM25Okapi (rank-bm25) |
| Fuzzy Scoring | RapidFuzz |
| Semantic Embeddings | sentence-transformers/all-MiniLM-L6-v2 |
| NLI Model | cross-encoder/nli-MiniLM2-L6-H768 |
| BERT Classifier | mrm8488/bert-tiny-finetuned-fake-news-detection |
| Explainability | LIME |
| Urdu Model | ikomil/bert-urdu-fake-news (HuggingFace) |
| Live News Index | GDELT Project API |
| Fact Check | Google Fact Check Tools API |
| AI Chatbot | Gemini 2.5 Flash (Google AI Studio) |
| Link Scraping | requests + BeautifulSoup4 |
| OCR (on-device) | Google ML Kit Text Recognition |
