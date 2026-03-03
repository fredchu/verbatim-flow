# Breeze-ASR-25 Integration Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Breeze-ASR-25 as a model option under the existing MLX Whisper engine, with automatic s2t skip for native Traditional Chinese output.

**Architecture:** Extend the existing MLX Whisper engine with a `MlxWhisperModel` enum (mirroring `QwenModel`). Python-side adds a native-Traditional model set to skip opencc conversion. Swift-side passes model ID through CLI `--model` flag (already supported by the Python script).

**Tech Stack:** Swift 5.9 (SPM), Python 3, mlx-whisper, opencc

---

### Task 1: Python — Add native-Traditional model detection

**Files:**
- Modify: `apps/mac-client/python/verbatim_flow/mlx_whisper_transcriber.py:121`
- Test: `apps/mac-client/python/tests/test_mlx_whisper_transcriber.py`

**Step 1: Write the failing test**

Add to `test_mlx_whisper_transcriber.py`:

```python
from verbatim_flow.mlx_whisper_transcriber import _is_native_traditional


class TestIsNativeTraditional:
    def test_breeze_mlx(self):
        assert _is_native_traditional("eoleedi/Breeze-ASR-25-mlx") is True

    def test_breeze_pytorch(self):
        assert _is_native_traditional("MediaTek-Research/Breeze-ASR-25") is True

    def test_whisper_large_v3(self):
        assert _is_native_traditional("mlx-community/whisper-large-v3-mlx") is False

    def test_empty_string(self):
        assert _is_native_traditional("") is False
```

Also update the import line at the top to include `_is_native_traditional`.

**Step 2: Run test to verify it fails**

Run: `cd apps/mac-client/python && python -m pytest tests/test_mlx_whisper_transcriber.py::TestIsNativeTraditional -v`
Expected: FAIL with `ImportError: cannot import name '_is_native_traditional'`

**Step 3: Write minimal implementation**

In `mlx_whisper_transcriber.py`, add after the `_TRADITIONAL_SUFFIXES` set (after line 32):

```python
# Models that natively output Traditional Chinese (no opencc s2t needed).
_NATIVE_TRADITIONAL_MODELS = {
    "eoleedi/Breeze-ASR-25-mlx",
    "MediaTek-Research/Breeze-ASR-25",
}


def _is_native_traditional(model_id: str) -> bool:
    """Return True if the model natively outputs Traditional Chinese."""
    return model_id in _NATIVE_TRADITIONAL_MODELS
```

Then modify the s2t conversion block (currently line 121-122):

Change:
```python
        if convert_trad and detected_lang in _TRADITIONAL_CHINESE_CODES:
            text = _convert_s2t(text)
```

To:
```python
        if convert_trad and detected_lang in _TRADITIONAL_CHINESE_CODES:
            if not _is_native_traditional(self.model_name):
                text = _convert_s2t(text)
```

**Step 4: Run test to verify it passes**

Run: `cd apps/mac-client/python && python -m pytest tests/test_mlx_whisper_transcriber.py -v`
Expected: ALL PASS (existing tests + new tests)

**Step 5: Commit**

```bash
git add apps/mac-client/python/verbatim_flow/mlx_whisper_transcriber.py apps/mac-client/python/tests/test_mlx_whisper_transcriber.py
git commit -m "feat(breeze-asr): add native-Traditional model detection to skip s2t"
```

---

### Task 2: Swift — Add MlxWhisperModel enum to CLIConfig

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/CLIConfig.swift`

**Step 1: Add the enum**

After the `QwenModel` enum (after line 55), add:

```swift
enum MlxWhisperModel: String, CaseIterable {
    case whisperLargeV3 = "mlx-community/whisper-large-v3-mlx"
    case breezeASR25    = "eoleedi/Breeze-ASR-25-mlx"

    var displayName: String {
        switch self {
        case .whisperLargeV3: return "Whisper Large V3"
        case .breezeASR25:    return "Breeze ASR 25"
        }
    }
}
```

**Step 2: Add `mlxWhisperModel` property to CLIConfig struct**

Find the struct properties (around line 80-90) and add `mlxWhisperModel: MlxWhisperModel = .whisperLargeV3` alongside the existing model properties.

**Step 3: Update `replacing()` helper**

Add `mlxWhisperModel` parameter to the `replacing()` method (around line 117-141), following the same pattern as `qwenModel`.

**Step 4: Add CLI flag parsing**

After the `--qwen-model` parsing block (around line 181-186), add:

```swift
case "--mlx-whisper-model":
    index += 1
    guard index < args.count, let model = MlxWhisperModel(rawValue: args[index]) else {
        throw ConfigError.invalidValue("--mlx-whisper-model", MlxWhisperModel.allCases.map(\.rawValue).joined(separator: " | "))
    }
    config = config.replacing(mlxWhisperModel: model)
```

**Step 5: Build to verify**

Run: `cd apps/mac-client && swift build 2>&1 | head -20`
Expected: BUILD SUCCEEDED (or errors only from files not yet updated)

**Step 6: Commit**

```bash
git add apps/mac-client/Sources/VerbatimFlow/CLIConfig.swift
git commit -m "feat(breeze-asr): add MlxWhisperModel enum and CLI flag"
```

---

### Task 3: Swift — Add AppPreferences for MlxWhisperModel

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/AppPreferences.swift`

**Step 1: Add preference key**

In the `Key` enum (line 6-14), add:

```swift
static let mlxWhisperModel = "verbatimflow.mlxWhisperModel"
```

**Step 2: Add load/save methods**

After the existing `saveQwenModel` (line 94), add:

```swift
func loadMlxWhisperModel() -> MlxWhisperModel? {
    guard let rawValue = defaults.string(forKey: Key.mlxWhisperModel) else {
        return nil
    }
    return MlxWhisperModel(rawValue: rawValue)
}

func saveMlxWhisperModel(_ model: MlxWhisperModel) {
    defaults.set(model.rawValue, forKey: Key.mlxWhisperModel)
}
```

**Step 3: Build to verify**

Run: `cd apps/mac-client && swift build 2>&1 | head -20`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add apps/mac-client/Sources/VerbatimFlow/AppPreferences.swift
git commit -m "feat(breeze-asr): add MlxWhisperModel preference persistence"
```

---

### Task 4: Swift — Wire MlxWhisperModel through AppController

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/AppController.swift`

**Step 1: Add property**

Near the existing `qwenModel` property (around line 29), add:

```swift
private var mlxWhisperModel: MlxWhisperModel = .whisperLargeV3
```

**Step 2: Add computed property**

Near the existing `currentQwenModel` (around line 121-123), add:

```swift
var currentMlxWhisperModel: MlxWhisperModel {
    mlxWhisperModel
}
```

**Step 3: Initialize from config**

In `init(config:)`, add initialization from config alongside `self.qwenModel = config.qwenModel`:

```swift
self.mlxWhisperModel = config.mlxWhisperModel
```

**Step 4: Add setter method**

After `setQwenModel()` (around line 323-336), add:

```swift
func setMlxWhisperModel(_ model: MlxWhisperModel) {
    guard model != mlxWhisperModel else { return }
    mlxWhisperModel = model
    rebuildTranscriber()
    emit("[config] MLX Whisper model set to \(model.displayName)")
}
```

**Step 5: Pass to SpeechTranscriber in rebuildTranscriber()**

In `rebuildTranscriber()` (around line 662), add `mlxWhisperModel: mlxWhisperModel` to the SpeechTranscriber initializer call.

**Step 6: Build to verify**

Run: `cd apps/mac-client && swift build 2>&1 | head -20`
Expected: Compile errors in SpeechTranscriber (expected — will fix in Task 5)

**Step 7: Commit**

```bash
git add apps/mac-client/Sources/VerbatimFlow/AppController.swift
git commit -m "feat(breeze-asr): wire MlxWhisperModel through AppController"
```

---

### Task 5: Swift — Pass model ID through SpeechTranscriber

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/SpeechTranscriber.swift`

**Step 1: Add stored property**

Near the existing `let qwenModel: QwenModel` (line 14), add:

```swift
let mlxWhisperModel: MlxWhisperModel
```

**Step 2: Update init to accept the new parameter**

Add `mlxWhisperModel: MlxWhisperModel` to the initializer parameters and assign `self.mlxWhisperModel = mlxWhisperModel`.

**Step 3: Update transcribeMlxWhisperAudioFile() signature**

Change the method (around line 862) from:

```swift
private nonisolated static func transcribeMlxWhisperAudioFile(
    audioURL: URL,
    languageCode: String?,
    outputLocale: String? = nil
) throws -> String
```

To:

```swift
private nonisolated static func transcribeMlxWhisperAudioFile(
    audioURL: URL,
    model: String,
    languageCode: String?,
    outputLocale: String? = nil
) throws -> String
```

**Step 4: Pass `--model` to the Python script**

Inside the method, add the `--model` argument to the process arguments, similar to how `transcribeQwenAudioFile()` does it:

```swift
process.arguments = [
    scriptURL.path,
    "--audio", audioURL.path,
    "--model", model,
]
```

**Step 5: Update the call site in stopMlxWhisperRecording()**

Where `transcribeMlxWhisperAudioFile()` is called (around line 414-454), add `model: mlxWhisperModel.rawValue`.

**Step 6: Build to verify**

Run: `cd apps/mac-client && swift build 2>&1 | head -20`
Expected: BUILD SUCCEEDED (or errors only from FailedRecordingStore — Task 6)

**Step 7: Commit**

```bash
git add apps/mac-client/Sources/VerbatimFlow/SpeechTranscriber.swift
git commit -m "feat(breeze-asr): pass model ID to mlx-whisper Python script"
```

---

### Task 6: Swift — Update FailedRecordingStore

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/FailedRecordingStore.swift`

**Step 1: Add field to Entry struct**

In the `Entry` struct (around line 4-35), add:

```swift
let mlxWhisperModelRawValue: String?
```

**Step 2: Add computed property**

```swift
var mlxWhisperModel: MlxWhisperModel? {
    mlxWhisperModelRawValue.flatMap { MlxWhisperModel(rawValue: $0) }
}
```

**Step 3: Update save() method**

Add `mlxWhisperModel: MlxWhisperModel?` parameter to `save()` (around line 82-126) and include `mlxWhisperModelRawValue: mlxWhisperModel?.rawValue` in the Entry initializer.

**Step 4: Update retry logic**

In `retryLastFailedRecording()`, for the `.mlxWhisper` case, extract `entry.mlxWhisperModel ?? .whisperLargeV3` and pass it to `transcribeMlxWhisperAudioFile()`.

**Step 5: Update all save() call sites**

Search for `FailedRecordingStore.save(` calls and add `mlxWhisperModel:` parameter.

**Step 6: Build to verify**

Run: `cd apps/mac-client && swift build 2>&1 | head -20`
Expected: BUILD SUCCEEDED

**Step 7: Commit**

```bash
git add apps/mac-client/Sources/VerbatimFlow/FailedRecordingStore.swift apps/mac-client/Sources/VerbatimFlow/SpeechTranscriber.swift
git commit -m "feat(breeze-asr): persist MlxWhisperModel in FailedRecordingStore"
```

---

### Task 7: Swift — Add menu UI for model selection

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/MenuBarApp.swift`

**Step 1: Add menu item declarations**

Near the existing Qwen model menu items (around line 82-93), add:

```swift
let mlxWhisperModelMenuItem = NSMenuItem(title: "MLX Whisper Model", action: nil)
let mlxWhisperModelWhisperV3Item = NSMenuItem(title: "Whisper Large V3", action: #selector(setMlxWhisperModelWhisperV3))
let mlxWhisperModelBreezeItem = NSMenuItem(title: "Breeze ASR 25", action: #selector(setMlxWhisperModelBreeze))
let mlxWhisperModelInfoItem = NSMenuItem(title: "", action: nil)
```

**Step 2: Add action methods**

```swift
@objc private func setMlxWhisperModelWhisperV3() {
    setMlxWhisperModel(.whisperLargeV3)
}

@objc private func setMlxWhisperModelBreeze() {
    setMlxWhisperModel(.breezeASR25)
}

private func setMlxWhisperModel(_ model: MlxWhisperModel) {
    controller.setMlxWhisperModel(model)
    preferences.saveMlxWhisperModel(controller.currentMlxWhisperModel)
    refreshEngineChecks()
}
```

**Step 3: Build the submenu**

In the menu construction area (near line 367-370, where Qwen submenu is built), add:

```swift
mlxWhisperModelWhisperV3Item.target = self
mlxWhisperModelBreezeItem.target = self

let mlxWhisperModelMenu = NSMenu()
mlxWhisperModelMenu.addItem(mlxWhisperModelWhisperV3Item)
mlxWhisperModelMenu.addItem(mlxWhisperModelBreezeItem)
mlxWhisperModelMenu.addItem(NSMenuItem.separator())
mlxWhisperModelMenu.addItem(mlxWhisperModelInfoItem)
mlxWhisperModelMenuItem.submenu = mlxWhisperModelMenu
```

Add `mlxWhisperModelMenuItem` to the settings submenu (near line 434, where `qwenModelMenuItem` is added).

**Step 4: Update refreshEngineChecks()**

In `refreshEngineChecks()`, add:

```swift
mlxWhisperModelMenuItem.isEnabled = currentEngine == .mlxWhisper
mlxWhisperModelInfoItem.isHidden = currentEngine != .mlxWhisper

let currentMlxModel = controller.currentMlxWhisperModel
mlxWhisperModelWhisperV3Item.state = currentMlxModel == .whisperLargeV3 ? .on : .off
mlxWhisperModelBreezeItem.state = currentMlxModel == .breezeASR25 ? .on : .off
mlxWhisperModelInfoItem.title = "Model: \(currentMlxModel.displayName)"
```

**Step 5: Add resolveMlxWhisperModel()**

Add a static method following the `resolveQwenModel()` pattern:

```swift
private static func resolveMlxWhisperModel(config: CLIConfig, preferences: AppPreferences) -> MlxWhisperModel {
    if hasCLIFlag("--mlx-whisper-model") {
        return config.mlxWhisperModel
    }
    return preferences.loadMlxWhisperModel() ?? config.mlxWhisperModel
}
```

Call it in `init(config:)` and pass the resolved value into the CLIConfig.

**Step 6: Build to verify**

Run: `cd apps/mac-client && swift build 2>&1 | head -20`
Expected: BUILD SUCCEEDED

**Step 7: Commit**

```bash
git add apps/mac-client/Sources/VerbatimFlow/MenuBarApp.swift
git commit -m "feat(breeze-asr): add MLX Whisper model selection menu"
```

---

### Task 8: Final build and verification

**Step 1: Full build**

Run: `cd apps/mac-client && swift build 2>&1`
Expected: BUILD SUCCEEDED with no warnings related to our changes

**Step 2: Run Python tests**

Run: `cd apps/mac-client/python && python -m pytest tests/test_mlx_whisper_transcriber.py -v`
Expected: ALL PASS

**Step 3: Verify menu renders**

Run the app and confirm:
- MLX Whisper Model submenu appears
- Shows Whisper Large V3 (checked) and Breeze ASR 25
- Switching models updates the info item
- Submenu only enabled when MLX Whisper engine is selected

**Step 4: Commit any final adjustments**

```bash
git commit -m "feat(breeze-asr): final build verification"
```
