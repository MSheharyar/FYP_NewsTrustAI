# Start the NewsTrustAI backend with local dev settings
# Run from repo root: .\backend\start_backend.ps1

$env:REQUIRE_AUTH = "false"   # skip Firebase token verification locally
$env:GEMINI_API_KEY = "AIzaSyBVkhCmU5TL8pKPzhIS7mebxOjp9OBfhFg"
$env:BERT_MODEL_NAME = "mrm8488/bert-tiny-finetuned-fake-news-detection"

Set-Location "$PSScriptRoot\python_code"
uvicorn main:app --reload --host 0.0.0.0 --port 8000
