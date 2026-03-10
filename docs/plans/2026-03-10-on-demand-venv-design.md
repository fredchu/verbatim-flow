# On-Demand Python venv 設計

> 日期：2026-03-10
> 狀態：已核准

## 問題

VerbatimFlow 的 .app bundle 不包含 Python .venv（1.4GB），從 /Applications/ 執行時找不到 Python 依賴（mlx-whisper、sherpa-onnx 等），靜默 fallback 到系統 python 導致功能失敗。

## 設計決策

| 問題 | 決策 |
|------|------|
| venv 建立時機 | App 啟動時檢查，不存在就建 |
| Setup 失敗處理 | Graceful degradation，app 繼續啟動（Apple 引擎可用） |
| UI 呈現 | macOS Notification + menu bar 狀態文字 |
| 系統 Python 偵測序 | /usr/bin/python3 → /opt/homebrew/bin/python3 → /usr/local/bin/python3 |
| venv 更新機制 | requirements.txt SHA256 hash 比對 |

## 架構

```
App 啟動
  → PythonEnvironmentManager.ensureReady()
    → 檢查 ~/Library/Application Support/VerbatimFlow/.venv/bin/python 是否存在
    → 比對 .requirements_hash 與 bundle 內 requirements.txt 的 SHA256
    → 不存在或 hash 不同 → 背景執行 setup
    → 存在且 hash 相同 → 直接就緒
```

## 元件

### 1. PythonEnvironmentManager（新檔案）

- `ensureReady()` — 啟動時呼叫，非同步背景執行
- `findSystemPython()` — 按序找系統 Python
- `createVenv()` — `python3 -m venv <path>`
- `installRequirements()` — `pip install -r requirements.txt`
- `writeHash()` / `checkHash()` — requirements.txt 的 SHA256 比對
- 狀態回調：通知 menu bar 更新顯示

### 2. PythonScriptRunner 修改

`resolvePythonExecutable` 候選路徑（最終版）：

1. `VERBATIMFLOW_PYTHON_PATH`（環境變數，開發者 override）
2. source tree .venv（開發時）
3. exec-relative .venv（開發時）
4. `~/Library/Application Support/VerbatimFlow/.venv`（一般使用者）— 不存在時觸發 on-demand setup
5. 不再 fallback 到系統 python

### 3. Build script 修改

把 `requirements.txt` 複製到 `Contents/Resources/python/requirements.txt`。

### 4. UI 呈現

- Setup 進行中：macOS 通知 + menu stateMenuItem 顯示狀態
- Setup 完成：通知「Python 環境設定完成」
- Setup 失敗：通知 + alert 顯示原因，app 繼續運行
- 找不到系統 Python：alert 引導安裝（`xcode-select --install`）

## Graceful Degradation

- Python 環境不可用時：Apple ASR + format-only 模式正常運作
- MLX Whisper / Qwen / faster-whisper 引擎選項 disabled 並灰顯
- local rewrite / punctuation post-processing 跳過

## 不做的事

- 不做進度條視窗
- 不阻止 app 啟動
- 不自動重試（失敗後使用者可從 menu 手動觸發重試）
