#!/usr/bin/env python3
"""ASR post-processing: punctuation restoration + terminology correction.

Usage:
    echo "raw asr text" | python postprocess_asr.py [--language zh-Hant] [--no-punctuation] [--no-terminology]

stdin: raw ASR text (UTF-8)
stdout: processed text (UTF-8)
stderr: log/error messages
"""

import argparse
import sys
import tarfile
import time
import urllib.request
from pathlib import Path

# Model configuration
MODEL_NAME = "sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8"
DOWNLOAD_URL = (
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/"
    "punctuation-models/{}.tar.bz2"
)


def _default_model_dir() -> Path:
    """~/Library/Application Support/VerbatimFlow/models/"""
    home = Path.home()
    return home / "Library" / "Application Support" / "VerbatimFlow" / "models"


def _ensure_model(model_dir: Path) -> Path:
    """Download and extract the punctuation model if not present."""
    model_file = model_dir / MODEL_NAME / "model.int8.onnx"
    if model_file.exists():
        return model_file
    model_dir.mkdir(parents=True, exist_ok=True)
    url = DOWNLOAD_URL.format(MODEL_NAME)
    archive_path = model_dir / f"{MODEL_NAME}.tar.bz2"
    print(f"Downloading punctuation model from {url} ...", file=sys.stderr)
    urllib.request.urlretrieve(url, archive_path)
    print(f"Extracting to {model_dir} ...", file=sys.stderr)
    with tarfile.open(archive_path, "r:bz2") as tar:
        tar.extractall(path=model_dir, filter="data")
    archive_path.unlink()
    if not model_file.exists():
        raise FileNotFoundError(f"Model file not found after extraction: {model_file}")
    size_mb = model_file.stat().st_size / 1e6
    print(f"Model ready: {model_file} ({size_mb:.0f} MB)", file=sys.stderr)
    return model_file


def _add_punctuation(text: str, model_dir: Path, language: str) -> str:
    """Add punctuation using sherpa-onnx, optionally convert to Traditional Chinese."""
    import sherpa_onnx
    from opencc import OpenCC

    model_path = str(_ensure_model(model_dir))
    config = sherpa_onnx.OfflinePunctuationConfig(
        model=sherpa_onnx.OfflinePunctuationModelConfig(
            ct_transformer=model_path,
        ),
    )
    punct = sherpa_onnx.OfflinePunctuation(config)
    result = punct.add_punctuation(text)

    if language.startswith("zh-Hant") or language == "zh":
        cc = OpenCC("s2t")
        result = cc.convert(result)

    return result


def _apply_terminology(text: str) -> str:
    """Apply terminology corrections."""
    from terminology import apply_terminology_regex
    return apply_terminology_regex(text)


def main():
    parser = argparse.ArgumentParser(description="ASR post-processing")
    parser.add_argument("--language", default="zh-Hant",
                        help="Language: zh-Hant, zh-Hans, en (default: zh-Hant)")
    parser.add_argument("--no-punctuation", action="store_true",
                        help="Skip punctuation restoration")
    parser.add_argument("--no-terminology", action="store_true",
                        help="Skip terminology correction")
    parser.add_argument("--model-dir", type=Path, default=None,
                        help="Model directory (default: ~/Library/Application Support/VerbatimFlow/models/)")
    args = parser.parse_args()

    model_dir = args.model_dir or _default_model_dir()

    text = sys.stdin.read().strip()
    if not text:
        print("", end="")
        sys.exit(0)

    start = time.time()

    if not args.no_punctuation:
        text = _add_punctuation(text, model_dir, args.language)

    if not args.no_terminology:
        text = _apply_terminology(text)

    elapsed = time.time() - start
    print(f"Post-processing done in {elapsed:.3f}s", file=sys.stderr)

    print(text, end="")


if __name__ == "__main__":
    main()
