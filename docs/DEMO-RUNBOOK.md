# NewsTrustAI — Defense Demo Runbook

Step-by-step guide for running the FYP defense demonstration. Read this before the exam room, not in it.

---

## Pre-demo checklist (night before)

- [ ] `.env` file is in `backend/python_code/` with all keys filled in
- [ ] `global_news_db.json` is present in `backend/python_code/`
- [ ] BERT model files are in `backend/python_code/model/`
- [ ] Flutter app is installed on the demo device (physical or emulator)
- [ ] `API_BASE_URL` in the app points to the machine that will run the server
- [ ] You have confirmed the WiFi/LAN IP of the server machine
- [ ] Tested at least one claim end-to-end the evening before

---

## Step 1 — Start the backend

Open a PowerShell terminal in the repo root:

```powershell
.\backend\start_backend.ps1
```

Or manually:

```powershell
.\.venv\Scripts\activate
$env:REQUIRE_AUTH = "false"   # remove this line if using Firebase auth
$env:APP_ENV      = "local"
uvicorn backend.python_code.main:app --host 0.0.0.0 --port 8000
```

**Confirm it's alive:**

```powershell
Invoke-RestMethod http://localhost:8000/health
# Expected: {"status": "ok", "version": "3.0"}
```

Wait for these log lines before touching the app:

```
INFO  BM25 index warmed up.
INFO  spaCy NER warmed up.
INFO  BERT model loaded: ...
```

The first startup takes 20–30 seconds (BERT and NLI models load into RAM). Subsequent restarts are faster.

---

## Step 2 — Connect the Flutter app

- **Android emulator:** API_BASE_URL is `http://10.0.2.2:8000`
- **Physical device (same WiFi):** API_BASE_URL is `http://<server-LAN-IP>:8000`

Find your LAN IP on Windows:

```powershell
ipconfig | Select-String "IPv4"
```

To rebuild the app with a specific URL:

```powershell
cd frontend\newstrustai
flutter run --dart-define=API_BASE_URL=http://192.168.1.x:8000
```

---

## Step 3 — Demo flow (suggested order)

### A. Text verification — English (strong match)

1. Tap **Verify Text** on the home screen
2. Enter: `Pakistan beat India by 6 wickets in the ICC Champions Trophy final`
3. Tap **Verify**
4. Expected: **Real** verdict, high confidence (~90%+), matched source shown

**What to point out:** BM25 retrieval found the article, fuzzy match scored it above threshold, NLI confirmed entailment, BERT agreed — all 7 stages passed.

---

### B. Text verification — Fake claim (entity swap)

1. Enter: `India beat Pakistan by 6 wickets in the ICC Champions Trophy final`
2. Tap **Verify**
3. Expected: **Unverified** or **Fake** — the entity-order guard catches the swapped result

**What to point out:** "India beat Pakistan" and "Pakistan beat India" contain the same bag of words. The NER key-facts guard now checks *order* of locations — this is the bug that was found and fixed during development. It's a concrete example of test-driven debugging.

---

### C. Text verification — Urdu

1. Enter: `پاکستان نے بھارت کو شکست دی` (Pakistan ne India ko shikast di)
2. Expected: Arabic-script detection routes to Urdu BERT model; verdict shown with Urdu BERT note

**What to point out:** Single endpoint auto-detects language. LIME is skipped for Urdu (300 HuggingFace API calls per perturbation is unusable); the BERT confidence is shown directly instead.

---

### D. Image / OCR verification

1. Tap **Scan Image**
2. Select a screenshot of a news headline (English text, good lighting)
3. OCR extracts the text; you can edit it before submitting
4. Tap **Verify Extracted Text**

**What to point out:** Bounding boxes show which text regions were detected. The quality score (blocks × avg-chars heuristic) helps the user know when re-scanning is needed.

---

### E. URL / Link verification

1. Tap **Verify Link**
2. Enter a news article URL (e.g. a Dawn or ARY News article)
3. Expected: Backend scrapes the article, runs the pipeline on its text, returns verdict

---

### F. Analytics dashboard

1. Tap **Dashboard** (bottom nav)
2. Show: verification history, fake/real/unverified breakdown chart, trending claims

---

### G. Result cache (viral claims)

1. Submit the same claim as in step A a second time
2. Expected: near-instant response, result shows `cached: true`

**What to point out:** Repeat claims (viral misinformation) hit the in-memory LRU cache (6h TTL, 512 items) and skip the 5–10s pipeline entirely.

---

### H. Degraded mode (optional — only demo if stable)

1. Temporarily block outbound internet on the server (disable WiFi) while the app is running
2. Submit a claim
3. Expected: amber "Some checks didn't finish" banner on the result screen
4. **Re-enable internet before continuing**

---

## Examiner questions — prepared answers

**"What happens if HuggingFace API is down?"**
The Urdu BERT call is wrapped in `safe_post_json`. If it times out or fails, the result carries `note: urdu_model_unavailable` and the app displays a plain-English message. The English pipeline is unaffected.

**"What's the latency?"**
First call: 5–10 seconds (NLI cross-encoder + BERT on CPU). Repeat claims: <100ms (cache hit). LIME adds ~2s on top when triggered (English fake verdicts only).

**"Why BM25 and not a vector database?"**
BM25 over a 36k-article flat JSON file needs zero infrastructure: no server, no index build step, fits in RAM (~200 MB). For the FYP timeline and a single-instance demo this is the right tradeoff. The scaling doc covers the 3-stage migration to SQLite+FTS5 → FAISS → dedicated service.

**"Why HuggingFace API for Urdu instead of a local model?"**
The `ikomil/bert-urdu-fake-news` model weights are ~420 MB. Bundling them locally adds 420 MB to the repo and requires PyTorch GPU or slow CPU inference on-device. The API call adds ~1s latency but keeps the repo lean and the inference quality identical.

**"What tests do you have?"**
26 pytest tests: pipeline verdicts, fuzzy matching, language detection, thread resilience, result cache (TTL + LRU), HTTP client failure modes, Urdu fallback, and auth config guard. CI runs them on every push to `main`. Coverage report is generated on each CI run.

**"What's not implemented?"**
TF Lite offline inference (deprioritised — 90 MB APK size impact, no quantisation toolchain in the FYP timeline). Google/Facebook social login deep-link callback on physical Android devices (works on emulator; Firebase OAuth config is complete). Both are documented in `docs/FYP-feature-status.md`.

---

## Recovery procedures

### Backend crashed / not responding

```powershell
# Check what's on port 8000
netstat -ano | findstr :8000
# Kill it
taskkill /PID <pid> /F
# Restart
.\backend\start_backend.ps1
```

Wait for the warmup log lines, then refresh the app.

### App shows "Verification failed" SnackBar

1. Check the server terminal — look for Python tracebacks
2. Confirm `GET http://localhost:8000/health` still returns `{"status": "ok"}`
3. If health fails, restart the server (above)
4. If health is fine, it's a transient external API failure — submit again

### Urdu result shows "Urdu model temporarily unavailable"

- HuggingFace API timed out or `HF_API_TOKEN` is missing
- The rest of the result is still valid; point out the graceful degradation
- Check `HF_API_TOKEN` is set in `.env` and not expired

### App cannot reach the server (connection refused)

- Confirm the device and server are on the same WiFi network
- Re-check the LAN IP: `ipconfig | Select-String "IPv4"`
- Rebuild the app: `flutter run --dart-define=API_BASE_URL=http://<correct-ip>:8000`

### "REQUIRE_AUTH=false is only allowed when APP_ENV is local/dev" error at startup

Set both together:
```powershell
$env:REQUIRE_AUTH = "false"; $env:APP_ENV = "local"
uvicorn backend.python_code.main:app --host 0.0.0.0 --port 8000
```

---

## Timing guide

| Demo segment | Estimated time |
|---|---|
| Server startup + warmup | 1–2 min |
| English text verify (steps A + B) | 3–4 min |
| Urdu verify (step C) | 1–2 min |
| Image OCR (step D) | 2–3 min |
| Link verify (step E) | 2 min |
| Dashboard + cache demo (F + G) | 2 min |
| Examiner Q&A | 10–15 min |
| **Total** | **~25 min** |
