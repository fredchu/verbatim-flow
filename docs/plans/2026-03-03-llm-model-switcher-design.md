# LLM Model Switcher 設計文件

> 日期：2026-03-03
> 分支：feat/local-rewrite（含 LocalRewriter LM Studio 遷移）

## 目的

提供 UI 讓使用者手動切換標點符號和 Local Rewrite 使用的 LLM model ID 與 system prompt，方便快速評估不同模型的效果。同時將 LocalRewriter 從 Ollama 遷移至 LM Studio（OpenAI-compatible API）。

## 資料流

```
UserDefaults (5 keys)
  ├── verbatimflow.llmBaseURL            → "http://localhost:1234"
  ├── verbatimflow.punctuationModel      → "qwen/qwen3-vl-8b"
  ├── verbatimflow.punctuationPrompt     → "你是標點符號專家..."
  ├── verbatimflow.localRewriteModel     → "qwen/qwen3-vl-8b"
  └── verbatimflow.localRewritePrompt    → "你是 VerbatimFlow 本地校正模式..."

讀取時機：
  ├── _add_punctuation() → Python 端
  │   Swift 在 spawn Python process 前注入 env vars：
  │     VERBATIMFLOW_LLM_BASE_URL  ← UserDefaults 或預設值
  │     VERBATIMFLOW_LLM_MODEL     ← UserDefaults 或預設值
  │     VERBATIMFLOW_LLM_PROMPT    ← UserDefaults 或預設值（新增）
  │
  └── LocalRewriter.rewrite() → Swift 端
      直接從 UserDefaults 讀取 model/prompt，fallback 到硬編碼預設值
      Base URL 也從 UserDefaults 讀取
```

## LocalRewriter Ollama → LM Studio 遷移

```
之前（Ollama）：
  URL:      localhost:11434/api/chat
  Env:      VERBATIMFLOW_OLLAMA_BASE_URL
  Env:      VERBATIMFLOW_LOCAL_REWRITE_MODEL
  Response: json["message"]["content"]

之後（LM Studio / OpenAI-compatible）：
  URL:      localhost:1234/v1/chat/completions
  Env:      VERBATIMFLOW_LLM_BASE_URL        ← 跟標點共用
  Env:      VERBATIMFLOW_LLM_REWRITE_MODEL
  Response: json["choices"][0]["message"]["content"]
```

共用 Base URL，各自獨立 Model ID 和 Prompt。

## UI 設計

獨立 NSWindow（約 500×600），從 Menu Bar Settings 子選單的 "LLM Settings..." 開啟。

```
┌─────────────────────────────────────────────────┐
│ LLM Settings                              [×]   │
├─────────────────────────────────────────────────┤
│                                                 │
│ ── General ──────────────────────────────────── │
│                                                 │
│ LM Studio Base URL:                             │
│ ┌─────────────────────────────────────────────┐ │
│ │ http://localhost:1234                       │ │
│ └─────────────────────────────────────────────┘ │
│                                                 │
│ ── Punctuation ──────────────────────────────── │
│                                                 │
│ Model ID:                                       │
│ ┌─────────────────────────────────────────────┐ │
│ │ qwen/qwen3-vl-8b                           │ │
│ └─────────────────────────────────────────────┘ │
│                                                 │
│ System Prompt:                                  │
│ ┌─────────────────────────────────────────────┐ │
│ │ 你是標點符號專家。請為以下中文語音辨識文字  │ │
│ │ 加上適當的全形標點符號（，。、？！：；「」  │ │
│ │ 『』《》）。只加標點，不改動任何文字內容。  │ │
│ │ 直接輸出結果，不要解釋。/no_think           │ │
│ └─────────────────────────────────────────────┘ │
│                                                 │
│ ── Local Rewrite ────────────────────────────── │
│                                                 │
│ Model ID:                                       │
│ ┌─────────────────────────────────────────────┐ │
│ │ qwen/qwen3-vl-8b                           │ │
│ └─────────────────────────────────────────────┘ │
│                                                 │
│ System Prompt:                                  │
│ ┌─────────────────────────────────────────────┐ │
│ │ 你是 VerbatimFlow 本地校正模式。            │ │
│ │ 將語音轉錄的口語文字改寫為通順的書面語。    │ │
│ │ 規則：...                                   │ │
│ └─────────────────────────────────────────────┘ │
│                                                 │
│              [ Reset Defaults ]  [ Save ]       │
│                                                 │
└─────────────────────────────────────────────────┘
```

- **Save** — 存入 UserDefaults，立即生效
- **Reset Defaults** — 清除 UserDefaults，欄位回填硬編碼預設值
- Model ID 用 NSTextField（單行），Prompt 用 NSTextView（多行，4-5 行高）

## 檔案變動清單

| 檔案 | 變動 |
|---|---|
| **新增** `LLMSettingsWindow.swift` | 獨立 NSWindow，5 個欄位 + Save/Reset 按鈕 |
| **修改** `AppPreferences.swift` | 新增 5 個 key 的 load/save/clear 方法 |
| **修改** `MenuBarApp.swift` | 加 "LLM Settings..." 選單項目，開啟視窗 |
| **修改** `LocalRewriter.swift` | Ollama → OpenAI-compatible 格式，讀 UserDefaults 取 model/prompt |
| **修改** `SpeechTranscriber.swift` | spawn Python 前注入 `VERBATIMFLOW_LLM_PROMPT` env var |
| **修改** `mlx_whisper_transcriber.py` | `_add_punctuation()` 新增讀取 `VERBATIMFLOW_LLM_PROMPT` env var |

不動的：CLIConfig.swift（不需要新 CLI 參數，UI-only 功能）
