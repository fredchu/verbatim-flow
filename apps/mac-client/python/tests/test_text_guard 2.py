from verbatim_flow.text_guard import TextGuard


def test_raw_mode_preserves_text():
    guard = TextGuard(mode="raw")
    result = guard.apply("  hello   world  ")
    assert result.text == "hello   world"
    assert result.fell_back_to_raw is False


def test_format_mode_only_formats():
    guard = TextGuard(mode="format-only")
    result = guard.apply("Hello ,world !")
    assert result.text == "Hello, world!"
    assert result.fell_back_to_raw is False
