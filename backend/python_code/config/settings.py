import os

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DATABASE_FILE = os.getenv(
    "DATABASE_FILE",
    os.path.join(BASE_DIR, "global_news_db.json")
)

MODEL_DIR = os.getenv("MODEL_DIR", "/home/ubuntu/news_bert_model")

VERIFY_THRESHOLD = int(os.getenv("VERIFY_THRESHOLD", "75"))

# If a claim contains named entities, require some overlap with the best matched
# evidence to prevent false positives when users edit names/places.
ENTITY_OVERLAP_MIN = float(os.getenv("ENTITY_OVERLAP_MIN", "0.34"))

CONF_HIGH = 95.0
CONF_SLIGHTLY_LOW = 88.0
CONF_LOW = 78.0
CONF_VERY_LOW = 65.0

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
}

GOOGLE_FACTCHECK_API_KEY = os.getenv("GOOGLE_FACTCHECK_API_KEY", "")
