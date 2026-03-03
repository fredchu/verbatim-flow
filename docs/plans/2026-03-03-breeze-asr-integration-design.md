# Breeze-ASR-25 整合設計

> 日期：2026-03-03
> 分支：從 `feat/local-rewrite` 或 `main` 建立新分支 `feat/breeze-asr`

## 目標

在現有 MLX Whisper 引擎下新增 Breeze-ASR-25 模型選項，讓使用者可在選單中切換模型。Breeze 原生輸出繁體中文，自動跳過 opencc s2t 轉換。

## 決策記錄

| 決策 | 選擇 | 理由 |
|------|------|------|
| 整合方式 | 擴充現有 MLX Whisper 引擎 | 程式碼改動最小，不新增 engine case |
| s2t 處理 | 自動跳過 | Python 端根據模型 ID 判斷，使用者不需額外操作 |

## 資料模型

新增 `MlxWhisperModel` enum（仿照 `WhisperModel`、`QwenModel`）：

```swift
enum MlxWhisperModel: String {
    case whisperLargeV3 = "mlx-community/whisper-large-v3-mlx"
    case breezeASR25    = "eoleedi/Breeze-ASR-25-mlx"

    var displayName: String {
        switch self {
        case .whisperLargeV3: return "Whisper Large V3"
        case .breezeASR25:    return "Breeze ASR 25"
        }
    }

    var nativeTraditionalChinese: Bool {
        switch self {
        case .breezeASR25: return true
        default: return false
        }
    }
}
```

## 端對端資料流

```
使用者選單選 "Breeze ASR 25"
    ↓
MenuBarApp.setMlxWhisperModel(.breezeASR25)
    ↓
AppController.setMlxWhisperModel() → rebuildTranscriber()
    ↓
AppPreferences.saveMlxWhisperModel()
    ↓
SpeechTranscriber 持有 mlxWhisperModel
    ↓
stopMlxWhisperRecording() → transcribeMlxWhisperAudioFile()
    ↓
Process: transcribe_mlx_whisper.py --model "eoleedi/Breeze-ASR-25-mlx"
    ↓
MlxWhisperTranscriber(model="eoleedi/Breeze-ASR-25-mlx")
    ↓
mlx_whisper.transcribe() → 偵測到 Breeze 模型 → 跳過 s2t
    ↓
stdout 輸出繁體中文
```

## 改動範圍

| 檔案 | 改動 |
|------|------|
| `CLIConfig.swift` | 新增 `MlxWhisperModel` enum + `--mlx-whisper-model` CLI flag |
| `AppPreferences.swift` | 新增 `saveMlxWhisperModel` / `loadMlxWhisperModel` |
| `MenuBarApp.swift` | 新增模型子選單（仿照 Qwen 模型選單模式） |
| `AppController.swift` | 新增 `setMlxWhisperModel()` + 傳遞到 transcriber |
| `SpeechTranscriber.swift` | `transcribeMlxWhisperAudioFile()` 傳入 model ID |
| `mlx_whisper_transcriber.py` | 新增 `_NATIVE_TRADITIONAL_MODELS` 清單，命中時跳過 s2t |
| `FailedRecordingStore.swift` | 持久化 mlxWhisperModel 供重試 |

不改動的檔案：
- `transcribe_mlx_whisper.py` — 已支援 `--model` 參數
- `AppError.swift` — 沿用既有 `mlxWhisperTranscriptionFailed`

## Python 端 s2t 跳過邏輯

```python
_NATIVE_TRADITIONAL_MODELS = {
    "eoleedi/Breeze-ASR-25-mlx",
    "MediaTek-Research/Breeze-ASR-25",
}

def _is_native_traditional(model_id: str) -> bool:
    return model_id in _NATIVE_TRADITIONAL_MODELS
```

在 `transcribe()` 最終決定 s2t 轉換處：

```python
if convert_trad and detected_lang in _TRADITIONAL_CHINESE_CODES:
    if not _is_native_traditional(self.model_name):  # 新增
        text = _convert_s2t(text)
```

## 選單 UI

```
Recognition Engine ▸
  ├─ Apple Speech
  ├─ Whisper
  ├─ OpenAI Cloud
  ├─ Qwen3 ASR
  └─ MLX Whisper

MLX Whisper Model ▸      ← 僅在 MLX Whisper 引擎時啟用
  ├─ ✓ Whisper Large V3   ← 預設
  └─   Breeze ASR 25
```

行為：
- 子選單僅在引擎為 `.mlxWhisper` 時 enabled
- 狀態列顯示 `Model: Breeze ASR 25`
- 切換模型時呼叫 `rebuildTranscriber()`
- 首次選擇 Breeze 且未快取時自動下載（Python 端 `_ensure_model()` 已處理）
