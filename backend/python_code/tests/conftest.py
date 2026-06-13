import json
import os
import pytest

FIXTURE_DIR = os.path.join(os.path.dirname(__file__), "fixtures")


@pytest.fixture
def mini_db():
    with open(os.path.join(FIXTURE_DIR, "mini_db.json"), encoding="utf-8") as f:
        return json.load(f)


@pytest.fixture
def mock_search_fn(mini_db):
    """Returns a search_fn(query, top_k) that does naive keyword overlap on the mini DB."""
    def _search(query, top_k=100):
        q_words = set(w.lower() for w in query.split() if len(w) >= 4)
        scored = []
        for art in mini_db:
            hay = (art["title"] + " " + art["summary"] + " " + art["body"]).lower()
            overlap = sum(1 for w in q_words if w in hay)
            if overlap:
                scored.append((overlap, art))
        scored.sort(key=lambda x: x[0], reverse=True)
        return [art for _, art in scored[:top_k]]
    return _search
