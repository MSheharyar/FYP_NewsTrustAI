from typing import Dict, Any
from utils.net import get_domain, domain_in_set
from config.settings import MAIN_SOURCE_DOMAINS, OTHER_MAJOR_DOMAINS, CONF_VERY_LOW, GDELT_MAX_RESULTS, GDELT_RESULT_LIMIT
from services.http_client import safe_get_json

_EMPTY = {
    "found_main": False,
    "found_other": False,
    "main_domains": [],
    "other_domains": [],
    "items": [],
}


def gdelt_lookup_domains(query: str, max_results: int = GDELT_MAX_RESULTS) -> Dict[str, Any]:
    q = (query or "").strip()
    if not q:
        return dict(_EMPTY)

    url = "https://api.gdeltproject.org/api/v2/doc/doc"
    params = {
        "query": q,
        "mode": "ArtList",
        "format": "json",
        "maxrecords": str(max_results),
        "formatdate": "1",
        "sort": "HybridRel",
    }

    data = safe_get_json(url, params=params, timeout=12)
    if data is None:
        return {"error": True, **_EMPTY}

    arts = data.get("articles", []) or []

    main_domains: set = set()
    other_domains: set = set()
    items = []

    for a in arts:
        link = (a.get("url") or "").strip()
        if not link:
            continue
        dom = get_domain(link)
        if domain_in_set(dom, MAIN_SOURCE_DOMAINS):
            main_domains.add(dom)
        elif domain_in_set(dom, OTHER_MAJOR_DOMAINS):
            other_domains.add(dom)
        if dom in main_domains or dom in other_domains:
            items.append({
                "url": link,
                "domain": dom,
                "title": a.get("title") or "",
                "seendate": a.get("seendate") or "",
            })

    return {
        "found_main": len(main_domains) > 0,
        "found_other": len(other_domains) > 0,
        "main_domains": sorted(main_domains),
        "other_domains": sorted(other_domains),
        "items": items[:GDELT_RESULT_LIMIT],
    }