# NewsTrustAI (Flutter + FastAPI)

AI-powered news fact-checking app. Submit a text claim, a URL, or a screenshot — the 7-stage pipeline (BM25 retrieval → fuzzy matching → NER key-facts guard → NLI → BERT → LIME → fusion) returns a verdict with confidence score and highlighted evidence.

**Stack:** Flutter (Dart) · FastAPI (Python 3.11) · Firebase Auth · Firestore · HuggingFace Inference API · spaCy · rank-bm25

## Repo layout

```
backend/python_code/   FastAPI backend, ML pipeline, pytest suite
frontend/newstrustai/  Flutter mobile app
docs/                  Architecture, feature status, demo runbook
```

## Backend quickstart

### 1. Prerequisites

- Python 3.11+
- A Firebase project with Email/Phone auth enabled (see [Firebase setup](#firebase-setup))
- API keys for HuggingFace, Google Fact Check, and Gemini (see [Environment variables](#environment-variables))

### 2. Create a virtual environment

```powershell
python -m venv .venv
.\.venv\Scripts\activate
pip install -r backend\python_code\requirements.txt
python -m spacy download en_core_web_sm
```

### 3. Configure environment variables

```powershell
copy backend\python_code\.env.example backend\python_code\.env
# Edit .env and fill in your API keys (see Environment variables section below)
```

For local development without auth:

```powershell
$env:REQUIRE_AUTH = "false"
$env:APP_ENV      = "local"
```

Or use the provided script: `.\backend\start_backend.ps1`

### 4. Run the server

```powershell
uvicorn backend.python_code.main:app --reload --host 0.0.0.0 --port 8000
```

Verify it's up: `GET http://localhost:8000/health` → `{"status": "ok", "version": "3.0"}`

### API endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/verify-text` | Verify a text claim (English or Urdu) |
| POST | `/verify-link` | Verify a news article by URL |
| POST | `/verify-image` | Verify OCR-extracted image text |
| GET | `/trending` | Recent articles from the local DB |
| POST | `/chat` | Gemini-powered contextual chatbot |
| GET | `/health` | Server liveness check |
| GET | `/debug-db` | DB stats (requires `DEBUG=true` + auth) |

### Run tests

```powershell
cd backend\python_code
python -m pytest -v --cov=. --cov-report=term-missing
```

### Evaluation metrics

```powershell
python backend/python_code/evaluation.py
```

Runs the pipeline on 10 labelled claims and reports Accuracy / Precision / Recall / F1:

| Pipeline | Accuracy | F1 |
|----------|----------|----|
| Hybrid (ensemble) | 80% | 81.8% |
| BERT-only | 70% | 72.7% |
| Hybrid without BERT | 60% | 66.7% |

---

## Flutter quickstart

```powershell
cd frontend\newstrustai
flutter pub get
flutter run --dart-define=API_BASE_URL=http://<YOUR_PC_IP>:8000
```

- Android emulator: use `http://10.0.2.2:8000`
- Physical device: use your machine's LAN IP (e.g. `http://192.168.1.x:8000`)

---

## Environment variables

Copy `backend/python_code/.env.example` to `backend/python_code/.env`. The `.env` file is gitignored — never commit real secrets.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `REQUIRE_AUTH` | No | `true` | Set `false` only with `APP_ENV=local` |
| `APP_ENV` | No | `production` | `local`/`dev`/`production` — guards the auth bypass |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Yes (prod) | — | Full JSON string of Firebase service account key |
| `HF_API_TOKEN` | Yes | — | HuggingFace Inference API token (for Urdu BERT) |
| `GOOGLE_FACTCHECK_API_KEY` | Yes | — | Google Fact Check Tools API key |
| `GEMINI_API_KEY` | Yes | — | Gemini API key (for /chat endpoint) |
| `URDU_MODEL_ID` | No | `ikomil/bert-urdu-fake-news` | HuggingFace model ID for Urdu classification |
| `BERT_MODEL_NAME` | No | `mrm8488/bert-tiny-finetuned-fake-news-detection` | Local BERT model folder name |
| `NLI_MODEL_NAME` | No | `cross-encoder/nli-MiniLM2-L6-H768` | NLI cross-encoder model |
| `DATABASE_FILE` | No | `global_news_db.json` | Path to the 36k-article JSON database |
| `LOG_LEVEL` | No | `INFO` | Python logging level |
| `CORS_ORIGINS` | No | `*` | Comma-separated allowed origins |
| `DEBUG` | No | `false` | Enables the `/debug-db` endpoint |
| `VERIFY_THRESHOLD` | No | `75` | Minimum fuzzy match score to attempt verification |

---

## Firebase setup

1. Go to [Firebase Console](https://console.firebase.google.com) → create or open project `newstrust-fall`
2. **Authentication → Sign-in method:** enable Email/Password and Phone
3. **Project Settings → Service Accounts → Generate new private key** → download JSON
4. Paste the full JSON content as the value of `FIREBASE_SERVICE_ACCOUNT_JSON` in your `.env`
5. For the Flutter app, `google-services.json` (Android) must be in `frontend/newstrustai/android/app/`

---

## Documentation

- [Demo Runbook](docs/DEMO-RUNBOOK.md) — step-by-step guide for running the defense demo
- [Feature Status](docs/FYP-feature-status.md) — objectives vs. delivered
- [Architecture & Scaling](docs/architecture/scaling-and-limitations.md) — design decisions and migration path
