import logging

from config.settings import GOOGLE_FACTCHECK_API_KEY, FACTCHECK_PAGE_SIZE, FACTCHECK_TIMEOUT
from services.http_client import safe_get_json

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
    return safe_get_json(url, params=params, timeout=FACTCHECK_TIMEOUT)