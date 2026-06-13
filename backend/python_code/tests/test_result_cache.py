import time
from services.result_cache import ResultCache


def test_cache_hit_on_normalized_text():
    cache = ResultCache(maxsize=10, ttl_seconds=60)
    cache.set("Pakistan beat India!!!", {"final_label": "real"})
    # Punctuation/case/whitespace differences must still hit.
    assert cache.get("  pakistan beat india ") == {"final_label": "real"}


def test_cache_miss_on_different_text():
    cache = ResultCache(maxsize=10, ttl_seconds=60)
    cache.set("Pakistan beat India", {"final_label": "real"})
    assert cache.get("Stock market crashed today") is None


def test_ttl_expiry():
    cache = ResultCache(maxsize=10, ttl_seconds=0)
    cache.set("some claim", {"final_label": "real"})
    time.sleep(0.01)
    assert cache.get("some claim") is None


def test_lru_eviction():
    cache = ResultCache(maxsize=2, ttl_seconds=60)
    cache.set("a long enough claim one", {"v": 1})
    cache.set("a long enough claim two", {"v": 2})
    cache.set("a long enough claim three", {"v": 3})  # evicts oldest
    assert cache.get("a long enough claim one") is None
    assert cache.get("a long enough claim three") == {"v": 3}
