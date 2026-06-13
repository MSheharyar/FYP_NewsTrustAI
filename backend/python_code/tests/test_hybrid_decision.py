# Monkeypatches `get_candidate_articles` and `safe_read_db` in services.verification
# (both are imported at module level from db.reader) to return the 6-article mini DB.
# External calls (google_factcheck, gdelt_lookup_domains) are silenced to keep tests offline.
import json
import os
import pytest
import services.verification as verification

FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "mini_db.json")


@pytest.fixture(autouse=True)
def _patch_db(monkeypatch):
    with open(FIXTURE, encoding="utf-8") as f:
        articles = json.load(f)

    monkeypatch.setattr(verification, "get_candidate_articles", lambda *a, **k: articles)
    monkeypatch.setattr(verification, "safe_read_db", lambda *a, **k: articles)
    monkeypatch.setattr(verification, "google_factcheck", lambda *a, **k: None)
    monkeypatch.setattr(verification, "gdelt_lookup_domains",
                        lambda *a, **k: {"found_main": False, "found_other": False})


def _label(result):
    for key in ("final_label", "label", "verdict"):
        if key in result:
            return result[key]
    return str(result)


def test_too_vague_input_is_rejected():
    result = verification.hybrid_decision("ok")
    assert "vague" in str(result).lower() or _label(result) in ("unverified", "input_too_vague")


def test_strong_db_match_verifies_real():
    result = verification.hybrid_decision("Pakistan beat India in the Champions Trophy final")
    assert _label(result) in ("real", "db_match", "verified")


def test_edited_claim_with_swapped_entity_is_not_verified_real():
    # DB says Pakistan beat India; claim says India beat Pakistan.
    result = verification.hybrid_decision("India beat Pakistan in the Champions Trophy final")
    assert _label(result) not in ("real", "verified")


def test_unrelated_claim_falls_through_to_unverified():
    result = verification.hybrid_decision("Aliens landed in the city center this morning")
    assert _label(result) in ("unverified", "no_evidence", "input_too_vague")
