import unittest

from verbatim_flow.text_guard import TextGuard


class TextGuardTests(unittest.TestCase):
    def test_raw_mode_preserves_text(self) -> None:
        guard = TextGuard(mode="raw")
        result = guard.apply("  hello   world  ")
        self.assertEqual(result.text, "hello   world")
        self.assertFalse(result.fell_back_to_raw)

    def test_format_mode_only_formats(self) -> None:
        guard = TextGuard(mode="format-only")
        result = guard.apply("Hello ,world !")
        self.assertEqual(result.text, "Hello, world!")
        self.assertFalse(result.fell_back_to_raw)


if __name__ == "__main__":
    unittest.main()
