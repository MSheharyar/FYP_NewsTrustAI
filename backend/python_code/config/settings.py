import os
from pathlib import Path
from dotenv import load_dotenv

BASE_DIR = Path(__file__).parent.parent

# Load .env from the package root (backend/python_code/.env) if it exists
load_dotenv(BASE_DIR / ".env")

DATABASE_FILE = os.getenv("DATABASE_FILE", str(BASE_DIR / "global_news_db.json"))

# Cross-platform: defaults to a "model" folder next to the package root
MODEL_DIR = os.getenv("MODEL_DIR", str(BASE_DIR / "model"))

LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()

VERIFY_THRESHOLD = int(os.getenv("VERIFY_THRESHOLD", "75"))

# If a claim contains named entities, require some overlap with the best matched
# evidence to prevent false positives when users edit names/places.
ENTITY_OVERLAP_MIN = float(os.getenv("ENTITY_OVERLAP_MIN", "0.34"))

# Confidence band thresholds
CONF_HIGH = float(os.getenv("CONF_HIGH", "95.0"))
CONF_SLIGHTLY_LOW = float(os.getenv("CONF_SLIGHTLY_LOW", "88.0"))
CONF_LOW = float(os.getenv("CONF_LOW", "78.0"))
CONF_VERY_LOW = float(os.getenv("CONF_VERY_LOW", "65.0"))

# Hybrid verification tuning (centralised from services/verification.py)
MIN_TEXT_LEN = int(os.getenv("MIN_TEXT_LEN", "35"))
SOFT_CANDIDATE_TOPK = int(os.getenv("SOFT_CANDIDATE_TOPK", "30"))
BERT_SUGGEST_REAL_THRESHOLD = float(os.getenv("BERT_SUGGEST_REAL_THRESHOLD", "0.90"))
BERT_SUSPECT_FAKE_THRESHOLD = float(os.getenv("BERT_SUSPECT_FAKE_THRESHOLD", "0.88"))
BERT_DISAGREEMENT_THRESHOLD = float(os.getenv("BERT_DISAGREEMENT_THRESHOLD", "0.92"))

# NLI / semantic search tuning (centralised from text_verifier.py)
NLI_MIN_SEMANTIC = float(os.getenv("NLI_MIN_SEMANTIC", "0.55"))
NLI_ENTAIL_THRESHOLD = float(os.getenv("NLI_ENTAIL_THRESHOLD", "0.70"))

# NLI and sentence-embedding model names.
# To upgrade NLI accuracy at the cost of more RAM, set:
#   NLI_MODEL_NAME=facebook/bart-large-mnli
# To use a stronger embedding model:
#   EMBED_MODEL_NAME=sentence-transformers/all-mpnet-base-v2
NLI_MODEL_NAME = os.getenv("NLI_MODEL_NAME", "cross-encoder/nli-MiniLM2-L6-H768")
EMBED_MODEL_NAME = os.getenv("EMBED_MODEL_NAME", "sentence-transformers/all-MiniLM-L6-v2")

# Comma-separated allowed CORS origins, e.g. "http://localhost:3000,https://myapp.com"
CORS_ORIGINS = [o.strip() for o in os.getenv("CORS_ORIGINS", "*").split(",") if o.strip()]

MAIN_SOURCE_DOMAINS = {
    "arynews.tv",
    "dawn.com",
    "bbc.com", "bbc.co.uk",
    "cnn.com", "edition.cnn.com",
}

OTHER_MAJOR_DOMAINS = {
    "reuters.com",
    "apnews.com",
    "aljazeera.com",
    "theguardian.com",
    "nytimes.com",
    "washingtonpost.com",
}

# Evidence staleness threshold (days)
STALE_THRESHOLD_DAYS = int(os.getenv("STALE_THRESHOLD_DAYS", "548"))  # 18 months

# BM25 / candidate retrieval
BM25_TOP_K = int(os.getenv("BM25_TOP_K", "150"))

# BERT inference
BERT_MAX_LENGTH = int(os.getenv("BERT_MAX_LENGTH", "256"))

# Google Fact Check API
FACTCHECK_PAGE_SIZE = int(os.getenv("FACTCHECK_PAGE_SIZE", "5"))
FACTCHECK_TIMEOUT = int(os.getenv("FACTCHECK_TIMEOUT", "5"))

# GDELT live lookup
GDELT_MAX_RESULTS = int(os.getenv("GDELT_MAX_RESULTS", "30"))
GDELT_RESULT_LIMIT = int(os.getenv("GDELT_RESULT_LIMIT", "6"))

# Link fetching
LINK_FETCH_TIMEOUT = int(os.getenv("LINK_FETCH_TIMEOUT", "20"))

# HuggingFace Inference API
HF_REQUEST_TIMEOUT = int(os.getenv("HF_REQUEST_TIMEOUT", "15"))

# Romanised Urdu detection
ROMAN_URDU_THRESHOLD = int(os.getenv("ROMAN_URDU_THRESHOLD", "3"))

GOOGLE_FACTCHECK_API_KEY = os.getenv("GOOGLE_FACTCHECK_API_KEY", "")

# Gemini API key for the AI chatbot endpoint
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")

# Urdu model — served via HuggingFace Inference API (zero storage on server)
HF_API_TOKEN = os.getenv("HF_API_TOKEN", "")
URDU_MODEL_ID = os.getenv("URDU_MODEL_ID", "ikomil/bert-urdu-fake-news")

# Firebase Admin SDK — service account JSON as a string, or leave blank to use
# GOOGLE_APPLICATION_CREDENTIALS / Application Default Credentials.
FIREBASE_SERVICE_ACCOUNT_JSON = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON", "")

# Set REQUIRE_AUTH=false to bypass token verification during local development.
REQUIRE_AUTH = os.getenv("REQUIRE_AUTH", "true").lower() not in ("0", "false", "no")
