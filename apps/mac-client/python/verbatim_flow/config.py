from __future__ import annotations

from dataclasses import dataclass
import argparse


@dataclass(frozen=True)
class AppConfig:
    mode: str
    hotkey: str
    language: str | None
    model: str
    compute_type: str
    audio_device_index: int
    dry_run: bool


DEFAULT_HOTKEY = "ctrl+shift+space"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="verbatim-flow mac client")
    parser.add_argument("--mode", choices=["raw", "format-only"], default="raw")
    parser.add_argument("--hotkey", default=DEFAULT_HOTKEY, help="e.g. ctrl+shift+space")
    parser.add_argument("--language", default=None, help="Whisper language code (zh, en, ...)" )
    parser.add_argument("--model", default="small", help="faster-whisper model name")
    parser.add_argument(
        "--compute-type",
        default="int8",
        choices=["int8", "int8_float16", "float16", "float32"],
        help="faster-whisper compute type",
    )
    parser.add_argument("--audio-device-index", type=int, default=0, help="ffmpeg avfoundation audio device index")
    parser.add_argument("--dry-run", action="store_true", help="do not inject text")
    parser.add_argument("--list-devices", action="store_true", help="print ffmpeg avfoundation devices and exit")
    return parser.parse_args()


def to_config(args: argparse.Namespace) -> AppConfig:
    return AppConfig(
        mode=args.mode,
        hotkey=args.hotkey,
        language=args.language,
        model=args.model,
        compute_type=args.compute_type,
        audio_device_index=args.audio_device_index,
        dry_run=args.dry_run,
    )
