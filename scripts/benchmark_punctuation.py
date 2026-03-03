#!/usr/bin/env python3
"""FunASR CT-Transformer punctuation model wrapper for benchmark."""

import time

from funasr import AutoModel
from opencc import OpenCC


class PunctuationModel:
    """Wrapper for FunASR CT-Transformer punctuation restoration."""

    def __init__(self):
        self.model = AutoModel(model="ct-punc", model_revision="v2.0.4")
        self.cc = OpenCC("s2t")

    def add_punctuation(self, text: str) -> str:
        """Add punctuation and convert to Traditional Chinese."""
        result = self.model.generate(input=text)
        punctuated = result[0]["text"]
        return self.cc.convert(punctuated)

    def add_punctuation_raw(self, text: str) -> str:
        """Add punctuation without OpenCC conversion."""
        result = self.model.generate(input=text)
        return result[0]["text"]

    def add_punctuation_timed(self, text: str) -> tuple[str, float]:
        """Add punctuation and return (result, elapsed_seconds)."""
        start = time.time()
        result = self.add_punctuation(text)
        elapsed = time.time() - start
        return result, round(elapsed, 3)
