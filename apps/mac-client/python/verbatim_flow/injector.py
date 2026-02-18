from __future__ import annotations

import subprocess
import time


def _run(command: list[str], input_text: str | None = None) -> str:
    proc = subprocess.run(
        command,
        input=input_text,
        text=True,
        capture_output=True,
        check=True,
    )
    return (proc.stdout or "").strip()


class MacTextInjector:
    def __init__(self) -> None:
        pass

    def insert(self, text: str) -> None:
        if not text:
            return

        previous_clipboard = self._read_clipboard()
        self._write_clipboard(text)
        self._paste_cmd_v()
        time.sleep(0.25)
        self._write_clipboard(previous_clipboard)

    def _read_clipboard(self) -> str:
        try:
            return _run(["pbpaste"])
        except Exception:
            return ""

    def _write_clipboard(self, text: str) -> None:
        subprocess.run(["pbcopy"], input=text, text=True, capture_output=True, check=True)

    def _paste_cmd_v(self) -> None:
        # Requires Accessibility permission for Terminal/iTerm and System Events.
        _run(
            [
                "osascript",
                "-e",
                'tell application "System Events" to keystroke "v" using command down',
            ]
        )
