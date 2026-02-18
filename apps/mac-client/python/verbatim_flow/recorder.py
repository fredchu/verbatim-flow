from __future__ import annotations

import os
import signal
import subprocess
import tempfile
import time
from dataclasses import dataclass


@dataclass(frozen=True)
class RecordingResult:
    wav_path: str
    duration_sec: float


class FFmpegRecorder:
    def __init__(self, audio_device_index: int = 0) -> None:
        self.audio_device_index = audio_device_index
        self._proc: subprocess.Popen[str] | None = None
        self._wav_path: str | None = None
        self._started_at: float | None = None

    def start(self) -> None:
        if self._proc is not None:
            raise RuntimeError("recorder already running")

        fd, wav_path = tempfile.mkstemp(prefix="verbatim-flow-", suffix=".wav")
        os.close(fd)

        cmd = [
            "ffmpeg",
            "-y",
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
            "-f",
            "avfoundation",
            "-i",
            f":{self.audio_device_index}",
            "-ac",
            "1",
            "-ar",
            "16000",
            wav_path,
        ]

        self._proc = subprocess.Popen(cmd)
        self._wav_path = wav_path
        self._started_at = time.time()

    def stop(self) -> RecordingResult:
        if self._proc is None or self._wav_path is None or self._started_at is None:
            raise RuntimeError("recorder is not running")

        proc = self._proc
        proc.send_signal(signal.SIGINT)
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)

        duration_sec = max(0.0, time.time() - self._started_at)

        wav_path = self._wav_path
        self._proc = None
        self._wav_path = None
        self._started_at = None
        return RecordingResult(wav_path=wav_path, duration_sec=duration_sec)


def list_audio_devices() -> str:
    cmd = [
        "ffmpeg",
        "-f",
        "avfoundation",
        "-list_devices",
        "true",
        "-i",
        "",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    # ffmpeg prints device list to stderr for this command.
    raw = proc.stderr.strip() or proc.stdout.strip()
    lines = [line for line in raw.splitlines() if "[AVFoundation indev" in line]
    if lines:
        return "\n".join(lines)
    return raw
