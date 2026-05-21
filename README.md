# NewsTrustAI (Flutter + FastAPI)

This repo contains:
- **`frontend/newstrustai/`**: Flutter app
- **`backend/python_code/`**: FastAPI backend

## Architecture & Limitations

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed system design, data flow, and known limitations.

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

### Evaluation and Metrics

To evaluate the system's performance on known claims:

```bash
python backend/python_code/evaluation.py
```

This runs the verification pipeline on a test dataset of 10 real/fake claims and computes metrics:
- Accuracy, Precision, Recall, F1 Score
- Comparison between pipelines: hybrid (ensemble), BERT-only, hybrid without BERT

Results are saved to `backend/python_code/evaluation_results.json`.

**Sample Results:**
- Hybrid pipeline: 80% accuracy, 81.8% F1
- BERT-only: 70% accuracy, 72.7% F1
- Hybrid no BERT: 60% accuracy, 66.7% F1

This demonstrates the ensemble approach improves reliability over model-only predictions.

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

