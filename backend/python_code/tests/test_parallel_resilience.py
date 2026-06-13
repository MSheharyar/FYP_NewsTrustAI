import pytest
from routes.verify import run_parallel_verification


def _ok_hybrid(text):
    return {"final_label": "unverified", "method": "no_evidence"}


def _boom(text, *a, **k):
    raise RuntimeError("NLI model crashed")


def test_nli_failure_does_not_kill_request():
    result = run_parallel_verification(
        "some claim text long enough to be valid input here",
        hybrid_fn=_ok_hybrid,
        nli_fn=_boom,
    )
    assert result["hybrid"] is not None
    assert result["nli"] is None
    assert result["degraded"] is True


def test_hybrid_failure_does_not_kill_request():
    result = run_parallel_verification(
        "some claim text long enough to be valid input here",
        hybrid_fn=_boom,
        nli_fn=lambda text, **k: {"verdict": "unverified"},
    )
    assert result["hybrid"] is None
    assert result["nli"] is not None
    assert result["degraded"] is True


def test_both_succeed_is_not_degraded():
    result = run_parallel_verification(
        "some claim text long enough to be valid input here",
        hybrid_fn=_ok_hybrid,
        nli_fn=lambda text, **k: {"verdict": "real"},
    )
    assert result["degraded"] is False
