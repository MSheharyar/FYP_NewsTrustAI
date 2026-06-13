import logging
import requests

logger = logging.getLogger(__name__)


def safe_get_json(url, params=None, headers=None, timeout=5):
    """GET a URL and return parsed JSON, or None on any failure
    (timeout, connection error, non-200, or non-JSON body)."""
    try:
        resp = requests.get(url, params=params, headers=headers, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        logger.warning("HTTP GET failed for %s: %s", url, exc)
        return None
    if resp.status_code != 200:
        logger.warning("HTTP GET %s returned status %s", url, resp.status_code)
        return None
    try:
        return resp.json()
    except ValueError as exc:
        logger.warning("HTTP GET %s returned non-JSON body: %s", url, exc)
        return None


def safe_post_json(url, json_body=None, headers=None, timeout=10):
    """POST a URL with a JSON body and return parsed JSON, or None on any failure."""
    try:
        resp = requests.post(url, json=json_body, headers=headers, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        logger.warning("HTTP POST failed for %s: %s", url, exc)
        return None
    if resp.status_code != 200:
        logger.warning("HTTP POST %s returned status %s", url, resp.status_code)
        return None
    try:
        return resp.json()
    except ValueError as exc:
        logger.warning("HTTP POST %s returned non-JSON body: %s", url, exc)
        return None
