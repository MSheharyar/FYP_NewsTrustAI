# NewsTrustAI (Flutter + FastAPI)

This repo contains:
- **`frontend/newstrustai/`**: Flutter app
- **`backend/python_code/`**: FastAPI backend

## Backend quickstart

### Run FastAPI

From repo root:

```bash
python -m venv .venv
.\.venv\Scripts\activate
python -m pip install -r backend\python_code\requirements.txt
uvicorn backend.python_code.main:app --reload --host 0.0.0.0 --port 8000
```

Endpoints:
- `POST /verify-text`
- `POST /analyze-link` (also available as `POST /verify-link`)
- `GET /trending`

### Generate trending DB locally (not committed)

The trending feed is stored in a local JSON file (ignored by git): `global_news_db.json`.

To generate/update it:

```bash
python backend\python_code\update_db.py
```

Optional environment variables:
- `DATABASE_FILE`: full path to the JSON DB (default: `backend/python_code/global_news_db.json`)
- `DB_DAYS_BACK`, `DB_MAX_PER_FEED`, `DB_FETCH_BODY`, `DB_BODY_MAX_CHARS`

### Model files

Large model artifacts are intentionally **not committed** (they previously caused pushes to time out).

If you want to enable local model inference, download/place your model directory somewhere and point the backend to it:
- Set `MODEL_DIR` to your model folder path

## Flutter quickstart

From `frontend/newstrustai/`:

```bash
flutter pub get
flutter run
```

### Configure API base URL

You can override the backend base URL without editing code:

```bash
flutter run --dart-define=API_BASE_URL=http://<YOUR_PC_IP>:8000
```

Notes:
- **Web** defaults to the production backend URL unless overridden.
- **Android emulator** should use `http://10.0.2.2:8000` to reach the host machine.

