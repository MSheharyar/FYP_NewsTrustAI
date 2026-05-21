import logging

import requests
from config.settings import GOOGLE_FACTCHECK_API_KEY, FACTCHECK_PAGE_SIZE, FACTCHECK_TIMEOUT

logger = logging.getLogger(__name__)

def google_factcheck(query: str):
    if not GOOGLE_FACTCHECK_API_KEY:
        return None

    url = "https://factchecktools.googleapis.com/v1alpha1/claims:search"
    params = {
        "query": query,
        "key": GOOGLE_FACTCHECK_API_KEY,
        "pageSize": FACTCHECK_PAGE_SIZE,
    }

    try:
        r = requests.get(url, params=params, timeout=FACTCHECK_TIMEOUT)
        if r.status_code != 200:
            logger.warning("Google Fact Check API returned status %d for query: %r", r.status_code, query)
            return None
        return r.json()
    except requests.exceptions.RequestException as e:
        logger.warning("Google Fact Check API request failed: %s", e)
        return None
    except ValueError as e:
        logger.warning("Google Fact Check API returned invalid JSON: %s", e)
        return None