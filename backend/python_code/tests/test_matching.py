from services.matching import score_match


def test_identical_text_scores_high():
    score = score_match("Pakistan beat India in the final", "Pakistan beat India in the final")
    assert score >= 90


def test_inversion_is_penalized():
    # Same words, opposite meaning. token_set_ratio would be ~100;
    # the inversion guard must drop it below an identical match.
    forward = score_match("Pakistan beat India", "Pakistan beat India")
    inverted = score_match("Pakistan beat India", "India beat Pakistan")
    assert inverted < forward
    assert inverted < 90  # must not read as a strong match


def test_unrelated_text_scores_low():
    score = score_match("polio vaccination drive", "stock exchange record high")
    assert score < 50
