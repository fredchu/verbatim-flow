from __future__ import annotations

from dataclasses import dataclass
import re


@dataclass(frozen=True)
class GuardResult:
    text: str
    fell_back_to_raw: bool


class TextGuard:
    def __init__(self, mode: str = "raw") -> None:
        self.mode = mode

    def apply(self, raw: str) -> GuardResult:
        raw = raw.strip()
        if not raw:
            return GuardResult(text="", fell_back_to_raw=False)

        if self.mode == "raw":
            return GuardResult(text=raw, fell_back_to_raw=False)

        formatted = self._format_only(raw)
        if self._tokens(raw) == self._tokens(formatted):
            return GuardResult(text=formatted, fell_back_to_raw=False)
        return GuardResult(text=raw, fell_back_to_raw=True)

    def _format_only(self, text: str) -> str:
        text = re.sub(r"\s+", " ", text)
        text = re.sub(r"\s+([,\.!?;:，。！？；：])", r"\1", text)
        text = re.sub(r"([,\.!?;:])(\S)", r"\1 \2", text)
        text = re.sub(r"([，。！？；：])\s+", r"\1", text)
        text = re.sub(r"\s+([)\]}>])", r"\1", text)
        text = re.sub(r"([(<\[{])\s+", r"\1", text)
        return text.strip()

    def _tokens(self, text: str) -> list[str]:
        return re.findall(r"[\w\u4e00-\u9fff]+", text.lower())
