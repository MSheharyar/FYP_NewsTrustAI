import services.urdu_bert as urdu


def test_missing_token_returns_unavailable(monkeypatch):
    monkeypatch.setattr(urdu, "HF_API_TOKEN", "", raising=False)
    result = urdu.urdu_bert_predict("کوئی خبر")
    assert result.get("note") == "urdu_model_unavailable"
    assert result.get("label") in (None, "unverified")


def test_hf_failure_returns_unavailable(monkeypatch):
    monkeypatch.setattr(urdu, "HF_API_TOKEN", "fake-token", raising=False)
    monkeypatch.setattr(urdu, "safe_post_json", lambda *a, **k: None, raising=False)
    result = urdu.urdu_bert_predict("کوئی خبر")
    assert result.get("note") == "urdu_model_unavailable"
