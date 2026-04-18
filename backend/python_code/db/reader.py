import json
import os
from config.settings import DATABASE_FILE

def safe_read_db():
    if not os.path.exists(DATABASE_FILE):
        return []
    try:
        with open(DATABASE_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except Exception:
        return []