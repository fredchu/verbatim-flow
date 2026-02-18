# verbatim-flow mac client (Python MVP)

## What this MVP does
- Hold global hotkey to record voice (`ctrl+shift+space` by default).
- Release hotkey to transcribe speech with `faster-whisper`.
- Apply `raw` or `format-only` output policy.
- Paste into the currently focused app (clipboard-restore strategy).

## Requirements
- macOS
- `ffmpeg` installed
- Python 3.9+
- Accessibility permission for Terminal/iTerm + System Events
- Microphone permission for terminal

## Quickstart
```bash
cd "/Users/axton/Documents/DailyWork🌴/Project Files/Code Projects/verbatim-flow/apps/mac-client/python"
./scripts/setup_env.sh
./scripts/run.sh --mode raw --model small
```

## Permission checklist (required)
- `System Settings > Privacy & Security > Accessibility`:
  - enable your terminal app (Terminal/iTerm)
  - enable `System Events`
- `System Settings > Privacy & Security > Input Monitoring`:
  - enable your terminal app
- `System Settings > Privacy & Security > Microphone`:
  - enable your terminal app

## Useful commands
- List capture devices:
```bash
./scripts/run.sh --list-devices
```

- Choose an audio device index:
```bash
./scripts/run.sh --audio-device-index 0
```

- Run in format-only mode:
```bash
./scripts/run.sh --mode format-only --model small
```

- Dry run (print only, no paste):
```bash
./scripts/run.sh --dry-run
```

- Low latency profile (recommended for daily typing):
```bash
./scripts/run.sh --mode raw --model small --compute-type int8 --audio-device-index 2
```

- Accuracy profile (higher latency):
```bash
./scripts/run.sh --mode raw --model medium --compute-type int8 --audio-device-index 2
```

## Notes
- First transcription triggers model download.
- If hotkey conflicts with system shortcuts, use `--hotkey`.
- This MVP is intentionally conservative: default is `raw` to avoid rewriting.
- If `int8_float16` is unsupported on your machine, the app now auto-falls back to `int8`.
