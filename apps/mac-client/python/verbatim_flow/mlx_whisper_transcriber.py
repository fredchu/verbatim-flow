from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
import sys
import urllib.request


@dataclass(frozen=True)
class TranscriptResult:
    text: str


# Whisper uses ISO 639-1 codes directly (not language names like Qwen/mlx-audio).
_LANGUAGE_MAP: dict[str, str] = {
    "zh": "zh",
    "en": "en",
    "de": "de",
    "es": "es",
    "fr": "fr",
    "it": "it",
    "pt": "pt",
    "ru": "ru",
    "ko": "ko",
    "ja": "ja",
    "yue": "yue",
}

# Languages whose model output may need Simplified → Traditional conversion.
_TRADITIONAL_CHINESE_CODES = {"zh", "yue"}

# Locale suffixes that indicate Traditional Chinese.
_TRADITIONAL_SUFFIXES = {"hant", "tw", "hk", "mo"}

# Models that natively output Traditional Chinese (no opencc s2t needed).
_NATIVE_TRADITIONAL_MODELS = {
    "eoleedi/Breeze-ASR-25-mlx",
    "MediaTek-Research/Breeze-ASR-25",
}


def _is_native_traditional(model_id: str) -> bool:
    """Return True if the model natively outputs Traditional Chinese."""
    return model_id in _NATIVE_TRADITIONAL_MODELS


def _resolve_language(code: str | None) -> tuple[str | None, bool | None]:
    """Resolve locale code to (whisper_language_code, should_convert_to_traditional).

    Returns (None, None) when code is None (auto-detect mode).
    """
    if code is None:
        return (None, None)
    parts = code.replace("_", "-").lower().split("-")
    prefix = parts[0]
    whisper_lang = _LANGUAGE_MAP.get(prefix)
    if whisper_lang is None:
        return (None, False)
    if whisper_lang in _TRADITIONAL_CHINESE_CODES:
        has_traditional_suffix = any(p in _TRADITIONAL_SUFFIXES for p in parts[1:])
        has_simplified_suffix = any(p in {"hans", "cn"} for p in parts[1:])
        convert = has_traditional_suffix or (not has_simplified_suffix)
        return (whisper_lang, convert)
    return (whisper_lang, False)


def _contains_cjk(text: str) -> bool:
    """Return True if *text* contains CJK Unified Ideograph characters."""
    return any("\u4e00" <= ch <= "\u9fff" for ch in text)


def _convert_s2t(text: str) -> str:
    """Convert Simplified Chinese to Traditional Chinese via opencc."""
    try:
        from opencc import OpenCC
        return OpenCC("s2t").convert(text)
    except ImportError:
        return text


def _model_cache_path(model_id: str) -> Path:
    """Return expected HuggingFace cache directory for a model."""
    org_model = model_id.replace("/", "--")
    return Path.home() / ".cache" / "huggingface" / "hub" / f"models--{org_model}"


def _add_punctuation(text: str) -> str:
    """Add punctuation to unpunctuated Chinese text via OpenAI-compatible LLM API."""
    if not text:
        return text

    import json
    import os

    base_url = os.environ.get("VERBATIMFLOW_LLM_BASE_URL", "http://localhost:1234")
    model = os.environ.get("VERBATIMFLOW_LLM_MODEL", "qwen/qwen3-vl-8b")

    payload = json.dumps({
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": (
                    "你是標點符號專家。請為以下中文語音辨識文字加上適當的全形標點符號"
                    "（，。、？！：；「」『』《》）。只加標點，不改動任何文字內容。"
                    "直接輸出結果，不要解釋。/no_think"
                ),
            },
            {"role": "user", "content": text},
        ],
        "temperature": 0.1,
        "max_tokens": 2048,
        "stream": False,
    }).encode()

    req = urllib.request.Request(
        f"{base_url}/v1/chat/completions",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            result = json.loads(resp.read())
            content = result["choices"][0]["message"]["content"].strip()
            return re.sub(r"<think>[\s\S]*?</think>", "", content).strip()
    except Exception:
        return text  # Fallback: return unpunctuated text


class MlxWhisperTranscriber:
    DEFAULT_MODEL = "mlx-community/whisper-large-v3-mlx"

    def __init__(self, model: str = DEFAULT_MODEL) -> None:
        self.model_name = model

    def _ensure_model(self) -> None:
        import os
        cached = _model_cache_path(self.model_name).exists()
        if not cached:
            os.environ["HF_HUB_OFFLINE"] = "0"
            print(f"[info] Downloading model {self.model_name}...", file=sys.stderr)

    def transcribe(self, audio_path: str, language: str | None = None,
                   output_locale: str | None = None) -> TranscriptResult:
        self._ensure_model()
        import mlx_whisper

        whisper_lang, convert_trad = _resolve_language(language)

        result = mlx_whisper.transcribe(
            audio_path,
            path_or_hf_repo=self.model_name,
            language=whisper_lang,
            word_timestamps=False,
        )
        text = result.get("text", "").strip()

        # Auto-detect mode: infer language from output.
        detected_lang = whisper_lang
        if detected_lang is None:
            info = result.get("language")
            if info and info in ("zh", "chinese", "yue", "cantonese"):
                detected_lang = "zh"

        # Fallback: CJK character heuristic.
        if detected_lang is None and _contains_cjk(text):
            detected_lang = "zh"

        # Decide s2t conversion in auto-detect mode.
        if convert_trad is None and detected_lang in _TRADITIONAL_CHINESE_CODES:
            if output_locale:
                _, convert_trad = _resolve_language(output_locale)
            else:
                convert_trad = True

        if convert_trad and detected_lang in _TRADITIONAL_CHINESE_CODES:
            if not _is_native_traditional(self.model_name):
                text = _convert_s2t(text)

        # Add punctuation for models that don't output it natively.
        if _is_native_traditional(self.model_name) and text:
            text = _add_punctuation(text)

        return TranscriptResult(text=text)
