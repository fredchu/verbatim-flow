import unittest

from verbatim_flow.transcriber import FasterWhisperTranscriber


class _FallbackProbeTranscriber(FasterWhisperTranscriber):
    def __init__(self, compute_type: str) -> None:
        super().__init__(model="tiny", compute_type=compute_type, language="en")
        self.calls: list[str] = []

    def _create_model(self, compute_type: str):
        self.calls.append(compute_type)
        if compute_type == "int8_float16":
            raise RuntimeError(
                "Requested int8_float16 compute type, but the target device or backend do not support efficient int8_float16 computation."
            )
        return object()


class TranscriberFallbackTests(unittest.TestCase):
    def test_fallback_to_int8_when_compute_type_is_unsupported(self) -> None:
        tr = _FallbackProbeTranscriber(compute_type="int8_float16")
        tr._ensure_model()
        self.assertEqual(tr.calls, ["int8_float16", "int8"])

    def test_no_fallback_needed_for_int8(self) -> None:
        tr = _FallbackProbeTranscriber(compute_type="int8")
        tr._ensure_model()
        self.assertEqual(tr.calls, ["int8"])


if __name__ == "__main__":
    unittest.main()
