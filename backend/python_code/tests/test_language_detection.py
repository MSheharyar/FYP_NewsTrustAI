from services.urdu_bert import is_urdu


def test_english_is_not_urdu():
    assert is_urdu("The prime minister announced a new education budget today") is False


def test_arabic_script_urdu_is_detected():
    assert is_urdu("وزیراعظم نے آج نئی تعلیمی بجٹ کا اعلان کیا ہے") is True


def test_romanized_urdu_is_detected():
    # Should trip the >=3 romanized-word rule ("yeh", "nahi", "hai", "mein", "aur").
    assert is_urdu("yeh baat sach nahi hai mein aur app dono jaante hain") is True


def test_short_english_with_no_urdu_words_is_not_urdu():
    assert is_urdu("stock market crashed") is False
