#!/usr/bin/env python3
"""sherpa-onnx CT-Transformer punctuation model wrapper for benchmark."""

import tarfile
import time
import urllib.request
from pathlib import Path

import sherpa_onnx
from opencc import OpenCC

MODEL_DIR = Path(__file__).parent / "models"
MODEL_NAME = "sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8"
MODEL_FILE = MODEL_DIR / MODEL_NAME / "model.int8.onnx"
DOWNLOAD_URL = (
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/"
    "punctuation-models/{}.tar.bz2"
)


def _ensure_model() -> Path:
    """Download and extract the punctuation model if not present."""
    if MODEL_FILE.exists():
        return MODEL_FILE
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    url = DOWNLOAD_URL.format(MODEL_NAME)
    archive_path = MODEL_DIR / f"{MODEL_NAME}.tar.bz2"
    print(f"Downloading punctuation model from {url} ...")
    urllib.request.urlretrieve(url, archive_path)
    print(f"Extracting to {MODEL_DIR} ...")
    with tarfile.open(archive_path, "r:bz2") as tar:
        tar.extractall(path=MODEL_DIR)
    archive_path.unlink()
    if not MODEL_FILE.exists():
        raise FileNotFoundError(f"Model file not found after extraction: {MODEL_FILE}")
    print(f"Model ready: {MODEL_FILE} ({MODEL_FILE.stat().st_size / 1e6:.0f} MB)")
    return MODEL_FILE


class PunctuationModel:
    """Wrapper for sherpa-onnx CT-Transformer punctuation restoration."""

    def __init__(self):
        model_path = str(_ensure_model())
        config = sherpa_onnx.OfflinePunctuationConfig(
            model=sherpa_onnx.OfflinePunctuationModelConfig(
                ct_transformer=model_path,
            ),
        )
        self.punct = sherpa_onnx.OfflinePunctuation(config)
        self.cc = OpenCC("s2t")

    def _run_bert(self, text: str) -> str:
        """Run punctuation model on text."""
        return self.punct.add_punctuation(text)

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
