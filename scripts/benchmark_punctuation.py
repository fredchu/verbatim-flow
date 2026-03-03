#!/usr/bin/env python3
"""FunASR CT-Transformer punctuation model wrapper for benchmark."""

import re
import time

from funasr import AutoModel
from opencc import OpenCC

# CJK placeholders: 天干(10) + 地支(12) + extras = 30 slots
_PLACEHOLDERS = list("甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉戌亥福祿壽喜財德仁義禮智")
# Match English word sequences (possibly with internal spaces/digits)
_EN_SEQ = re.compile(r'[A-Za-z]+(?:[\s]+[A-Za-z0-9]+)*')


def _protect_english(text):
    """Replace English sequences with single CJK placeholders before BERT."""
    spans = []

    def _replace(m):
        i = len(spans)
        spans.append(m.group())
        if i < len(_PLACEHOLDERS):
            return _PLACEHOLDERS[i]
        return m.group()  # fallback: keep as-is if too many

    protected = _EN_SEQ.sub(_replace, text)
    return protected, spans


def _restore_english(text, spans):
    """Restore original English text from CJK placeholders."""
    for i, eng in enumerate(spans):
        if i < len(_PLACEHOLDERS):
            text = text.replace(_PLACEHOLDERS[i], eng, 1)
    return text


class PunctuationModel:
    """Wrapper for FunASR CT-Transformer punctuation restoration."""

    def __init__(self):
        self.model = AutoModel(model="ct-punc", model_revision="v2.0.4")
        self.cc = OpenCC("s2t")

    def _run_bert(self, text: str) -> str:
        """Run BERT with English protection."""
        protected, spans = _protect_english(text)
        result = self.model.generate(input=protected)
        punctuated = result[0]["text"]
        return _restore_english(punctuated, spans)

    def add_punctuation(self, text: str) -> str:
        """Add punctuation and convert to Traditional Chinese."""
        result = self._run_bert(text)
        return self.cc.convert(result)

    def add_punctuation_raw(self, text: str) -> str:
        """Add punctuation without OpenCC conversion."""
        return self._run_bert(text)

    def add_punctuation_timed(self, text: str) -> tuple[str, float]:
        """Add punctuation and return (result, elapsed_seconds)."""
        start = time.time()
        result = self.add_punctuation(text)
        elapsed = time.time() - start
        return result, round(elapsed, 3)
