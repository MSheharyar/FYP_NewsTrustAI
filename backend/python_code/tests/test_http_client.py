import requests
from services.http_client import safe_get_json


class _Resp:
    def __init__(self, status, payload=None, raise_json=False):
        self.status_code = status
        self._payload = payload
        self._raise_json = raise_json

    def json(self):
        if self._raise_json:
            raise ValueError("no json")
        return self._payload


def test_returns_payload_on_200(monkeypatch):
    monkeypatch.setattr(requests, "get", lambda *a, **k: _Resp(200, {"ok": True}))
    assert safe_get_json("http://x") == {"ok": True}


def test_returns_none_on_non_200(monkeypatch):
    monkeypatch.setattr(requests, "get", lambda *a, **k: _Resp(429))
    assert safe_get_json("http://x") is None


def test_returns_none_on_timeout(monkeypatch):
    def _raise(*a, **k):
        raise requests.exceptions.Timeout()
    monkeypatch.setattr(requests, "get", _raise)
    assert safe_get_json("http://x", timeout=1) is None


def test_returns_none_on_bad_json(monkeypatch):
    monkeypatch.setattr(requests, "get", lambda *a, **k: _Resp(200, raise_json=True))
    assert safe_get_json("http://x") is None
