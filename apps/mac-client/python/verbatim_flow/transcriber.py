from __future__ import annotations

from dataclasses import dataclass
import sys


@dataclass(frozen=True)
class TranscriptResult:
    text: str


class FasterWhisperTranscriber:
    def __init__(self, model: str = "small", compute_type: str = "int8", language: str | None = None) -> None:
        self.model = model
        self.compute_type = compute_type
        self.language = language
        self._model = None
        self._active_compute_type: str | None = None

    def _create_model(self, compute_type: str):
        from faster_whisper import WhisperModel

        return WhisperModel(self.model, device="auto", compute_type=compute_type)

    def _is_unsupported_compute_type_error(self, exc: Exception) -> bool:
        text = str(exc).lower()
        markers = [
            "requested",
            "compute type",
            "do not support efficient",
        ]
        return all(marker in text for marker in markers)

    def _ensure_model(self):
        if self._model is None:
            try:
                self._model = self._create_model(self.compute_type)
                self._active_compute_type = self.compute_type
            except Exception as exc:
                # Some backends reject int8_float16/float16 on specific hardware.
                if self.compute_type != "int8" and self._is_unsupported_compute_type_error(exc):
                    fallback = "int8"
                    print(
                        f"[warn] compute-type '{self.compute_type}' unsupported on this device. "
                        f"Falling back to '{fallback}'.",
                        file=sys.stderr,
                    )
                    self._model = self._create_model(fallback)
                    self._active_compute_type = fallback
                else:
                    raise

    def transcribe(self, wav_path: str) -> TranscriptResult:
        self._ensure_model()
        segments, _info = self._model.transcribe(
            wav_path,
            language=self.language,
            vad_filter=True,
            beam_size=1,
            temperature=0,
            condition_on_previous_text=False,
        )

        parts = [seg.text.strip() for seg in segments]
        text = " ".join([p for p in parts if p]).strip()
        return TranscriptResult(text=text)
