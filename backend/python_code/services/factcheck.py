import requests
from config.settings import GOOGLE_FACTCHECK_API_KEY

def google_factcheck(query: str):
    if not GOOGLE_FACTCHECK_API_KEY:
        return None

    url = "https://factchecktools.googleapis.com/v1alpha1/claims:search"
    params = {
        "query": query,
        "key": GOOGLE_FACTCHECK_API_KEY,
        "pageSize": 5
    }

    try:
        r = requests.get(url, params=params, timeout=10)
        if r.status_code != 200:
            return None
        return r.json()
    except Exception:
        return None