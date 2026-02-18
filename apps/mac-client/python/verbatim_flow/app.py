from __future__ import annotations

from dataclasses import dataclass
import os
import threading

from .config import AppConfig
from .hotkey import HoldToTalkHotkeyMonitor
from .injector import MacTextInjector
from .recorder import FFmpegRecorder
from .text_guard import TextGuard
from .transcriber import FasterWhisperTranscriber


@dataclass
class RuntimeState:
    is_recording: bool = False
    is_processing: bool = False


class VerbatimFlowApp:
    def __init__(self, config: AppConfig) -> None:
        self.config = config
        self.state = RuntimeState()
        self._state_lock = threading.Lock()

        self.recorder = FFmpegRecorder(audio_device_index=config.audio_device_index)
        self.transcriber = FasterWhisperTranscriber(
            model=config.model,
            compute_type=config.compute_type,
            language=config.language,
        )
        self.guard = TextGuard(mode=config.mode)
        self.injector = MacTextInjector()

        self.hotkey = HoldToTalkHotkeyMonitor(
            combo=config.hotkey,
            on_press=self._handle_press,
            on_release=self._handle_release,
        )

    def run(self) -> None:
        print("verbatim-flow (python)")
        print(
            f"mode={self.config.mode} hotkey={self.config.hotkey} "
            f"model={self.config.model} compute-type={self.config.compute_type}"
        )
        print("hold hotkey to record; release to transcribe")
        print("press Ctrl+C to exit")
        self.hotkey.start()
        self.hotkey.join()

    def _handle_press(self) -> None:
        with self._state_lock:
            if self.state.is_recording or self.state.is_processing:
                return
            self.state.is_recording = True

        try:
            self.recorder.start()
            print("[recording] ...")
        except Exception as exc:
            with self._state_lock:
                self.state.is_recording = False
            print(f"[error] failed to start recording: {exc}")

    def _handle_release(self) -> None:
        with self._state_lock:
            if not self.state.is_recording:
                return
            self.state.is_recording = False
            self.state.is_processing = True

        try:
            result = self.recorder.stop()
        except Exception as exc:
            with self._state_lock:
                self.state.is_processing = False
            print(f"[error] failed to stop recording: {exc}")
            return

        worker = threading.Thread(target=self._process_audio, args=(result.wav_path, result.duration_sec), daemon=True)
        worker.start()

    def _process_audio(self, wav_path: str, duration_sec: float) -> None:
        try:
            if duration_sec < 0.18:
                print("[skip] too short")
                return

            transcript = self.transcriber.transcribe(wav_path)
            guarded = self.guard.apply(transcript.text)

            if not guarded.text:
                print("[skip] empty transcript")
                return

            if guarded.fell_back_to_raw:
                print("[guard] semantic change detected, fallback to raw")

            if self.config.dry_run:
                print(f"[dry-run] {guarded.text}")
                return

            self.injector.insert(guarded.text)
            print(f"[inserted] {guarded.text}")
        except Exception as exc:
            print(f"[error] processing failed: {exc}")
        finally:
            try:
                if os.path.exists(wav_path):
                    os.remove(wav_path)
            finally:
                with self._state_lock:
                    self.state.is_processing = False
