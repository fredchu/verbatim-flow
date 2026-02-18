# Architecture (MVP)

## Pipeline
1. Global hotkey monitor (`pynput`, hold-to-talk)
2. Audio capture (`ffmpeg` + `avfoundation`, 16k mono wav)
3. ASR decode (`faster-whisper`, local model)
4. Guard stage
   - Raw mode: pass-through
   - Format-only mode: punctuation/spacing/case only
   - Reject semantic edits and fallback to raw
5. Text injection (`pbcopy` + AppleScript Cmd+V + clipboard restore)

## Design constraints
- Maximize time-to-first-token.
- Preserve deterministic behavior in guard stage.
- Keep ASR backend swappable (local model or cloud API).

## Current runtime path
- `/Users/axton/Documents/DailyWork🌴/Project Files/Code Projects/verbatim-flow/apps/mac-client/python`

## Native path status
- Swift native shell exists as an experiment under `/Users/axton/Documents/DailyWork🌴/Project Files/Code Projects/verbatim-flow/apps/mac-client`.
- Current machine has SDK/compiler mismatch that blocks Swift build, so Python path is used for active iteration.

## Interfaces (draft)
- `AsrEngine.transcribeStream(audioChunk): PartialTranscript`
- `TextGuard.apply(raw, mode): GuardedTranscript`
- `TextInjector.insert(text): Result`
