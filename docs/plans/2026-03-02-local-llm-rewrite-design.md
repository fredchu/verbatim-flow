# Local LLM Rewrite Mode Design

Date: 2026-03-02

## Problem

MLX Whisper Large V3 轉錄後的繁體中文文字需要語意重寫（去口語贅詞、修正同音字、加標點、潤飾句式）。現有 Clarify 模式使用雲端 API（OpenAI/OpenRouter），需要新增一個完全離線的本地 LLM 校正模式。

## Constraints

- Hardware: M1 Max 32GB，MLX Whisper (~3GB) 共存
- Latency: 3-8 秒可接受
- Quality: 完整語意重寫，多領域（財經、技術、日常），台灣繁體中文
- 混合錄音長度：短句 (20 字) 到長段 (500 字)

## Model Selection: Qwen3 8B

| 候選 | 記憶體 | 速度 | 中文品質 | 結論 |
|------|--------|------|----------|------|
| Qwen3 14B (現狀) | 11GB | ~20-30 tok/s | 優秀 | 散熱過重，排除 |
| **Qwen3 8B** | **6.8GB** | **35-50 tok/s** | **優秀 (≈Qwen2.5-14B)** | **選定** |
| Qwen3 4B | 3.7GB | 80-100 tok/s | 良好 (≈Qwen2.5-7B) | 備選（品質不足） |
| Qwen3 30B-A3B MoE | 21GB | 30-50 tok/s | 最佳 | 記憶體緊繃，排除 |
| DeepSeek-R1 7B | 4.9GB | 35-50 tok/s | 良好 | 推理導向，不適合改寫 |

Qwen3 8B 使用 Q4_K_M 量化，記憶體 ~6.8GB，與 MLX Whisper 共存後仍剩 ~22GB。

## Architecture

### Pipeline Position

```
Audio → MLX Whisper → Raw Text
                        ↓
              TextGuard(localRewrite)
                        ↓
              TerminologyDictionary
                        ↓
              MixedLanguageEnhancer
                        ↓
              LocalRewriter (LM Studio / OpenAI API)  ← NEW
                        ↓
              TextInjector → Focused App
```

`LocalRewriter` 與 `ClarifyRewriter` 平行——相同管線位置，不同後端。

### New TextGuard Mode

在 `CLIConfig.swift` 的 TextGuardMode enum 新增 `localRewrite` case。行為與 `clarify` 相同的前處理（去贅詞、合併重複），但後端改走 `LocalRewriter`。

### LocalRewriter.swift

新增 `LocalRewriter.swift`，結構參考 `ClarifyRewriter.swift`：

```swift
enum LocalRewriter {
    static func rewrite(text: String, localeIdentifier: String) throws -> LocalRewriteResult
}
```

- HTTP POST to `http://localhost:1234/v1/chat/completions` (OpenAI-compatible)
- 相容任何 OpenAI chat completions 端點（LM Studio / Ollama）
- 同步請求（與 ClarifyRewriter 一致，使用 DispatchSemaphore）

### LLM API Call

```json
{
  "model": "qwen/qwen3-vl-8b",
  "messages": [
    {"role": "system", "content": "<system prompt>"},
    {"role": "user", "content": "locale=zh-Hant\n\n<transcribed text>"}
  ],
  "temperature": 0.1,
  "max_tokens": 2048,
  "stream": false
}
```

### System Prompt

```
你是 VerbatimFlow 本地校正模式。
將語音轉錄的口語文字改寫為通順的書面語。
規則：
- 保持原意、事實、數字、專有名詞不變。
- 不添加原文沒有的資訊。
- 去除口語贅詞（嗯、啊、然後、就是說、對、那個）和明顯重複。
- 保持與輸入相同的語言（中文維持中文，中英混合維持混合）。
- 使用台灣繁體中文用語和全形標點符號（，。！？；：）。
- 僅輸出改寫後的純文字，不要 markdown，不要解釋。 /no_think
```

末尾 `/no_think` 指令讓 Qwen3 跳過思維鏈，直接輸出改寫結果。

### Configuration

| 環境變數 | 預設值 | 說明 |
|----------|--------|------|
| `VERBATIMFLOW_LLM_BASE_URL` | `http://localhost:1234` | LLM API 端點 |
| `VERBATIMFLOW_LLM_MODEL` | `qwen/qwen3-vl-8b` | 模型名稱 |

也支援 `~/.config/openai-settings.json`（與 ClarifyRewriter 共用設定載入邏輯）。

### UI Changes (MenuBarApp.swift)

Text Guard 選單新增選項：

```
◉ Raw
◯ Format Only
◯ Clarify (Cloud)
◯ Local Rewrite (LM Studio)   ← NEW
```

### Error Handling

| 錯誤情境 | 處理方式 |
|----------|----------|
| LLM server 未啟動 | 拋出 `AppError` 提示「Please start LLM server first」 |
| 模型未下載 | 拋出 `AppError` 提示「Please download the model first」 |
| 逾時 (30s) | 拋出 `AppError`，文字 fallback 到 TextGuard formatOnly 結果 |
| 空回應 | 拋出 `AppError`，fallback 同上 |

### Performance Estimates

| 輸入長度 | 輸出 tokens | Qwen3 8B 延遲 |
|----------|------------|---------------|
| 20 字 | ~30-60 | 0.75-1.5 秒 |
| 100 字 | ~150-250 | 3.75-6.25 秒 |
| 500 字 | ~500-800 | 12.5-20 秒 |

長段 (500+ 字) 可能超過 8 秒目標，但這是少數情境。

## Files to Create/Modify

| 檔案 | 變更 |
|------|------|
| `LocalRewriter.swift` | **新增**：LLM API HTTP 呼叫邏輯 |
| `CLIConfig.swift` | 修改：TextGuardMode 新增 `localRewrite` |
| `AppPreferences.swift` | 修改：持久化 localRewrite 設定 |
| `AppController.swift` | 修改：commitTranscript 加入 LocalRewriter 路由 |
| `MenuBarApp.swift` | 修改：Text Guard 選單新增選項 |
| `TextGuard.swift` | 修改：localRewrite mode 前處理（可複用 clarify 邏輯）|

## Testing Strategy

- Unit tests for LocalRewriter HTTP request construction (mock LLM response)
- Integration test with real LM Studio (manual, not CI)
- Test error scenarios: LLM server down, wrong model, timeout
