from urllib.parse import urlparse

def get_domain(url: str) -> str:
    """
    Extract normalized domain from a URL.
    Example:
      https://edition.cnn.com/foo -> edition.cnn.com
    """
    if not url:
        return ""
    try:
        host = urlparse(url).netloc.lower()
        return host.replace("www.", "").strip()
    except Exception:
        return ""


def domain_in_set(domain: str, domain_set: set) -> bool:
    """
    Checks if domain belongs to a trusted domain set.
    Handles:
      - subdomains (edition.cnn.com)
      - mobile/amp domains (m.bbc.co.uk, amp.cnn.com)
    """
    if not domain:
        return False

    d = domain.lower().replace("www.", "").strip()

    for trusted in domain_set:
        t = trusted.lower().replace("www.", "").strip()

        # Exact match
        if d == t:
            return True

        # Subdomain match
        if d.endswith("." + t):
            return True

    return False
