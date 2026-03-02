# 研究：使用 `claude -p` CLI 做轉錄校正的可行性分析

> 日期：2026-03-02
> 狀態：研究筆記

## 背景

VerbatimFlow 目前的校正流程：

```
ASR 轉錄文字
  → TextGuard (format-only / clarify normalize)
  → TerminologyDictionary (自定替換)
  → MixedLanguageEnhancer (中英混合校正)
  → [可選] ClarifyRewriter (OpenAI/OpenRouter LLM 重寫)
```

本研究探討：在 ASR 轉錄完成後，用 Claude Code 的 `claude -p` 指令搭配 Haiku 或 Sonnet 模型做校正的可行性。

---

## `claude -p` 基本用法

`claude -p` 是 Claude Code CLI 的 **headless 模式**（也稱 print mode / pipe mode），適合非互動式的自動化用途。

### 基本語法

```bash
# 直接傳入 prompt
claude -p "校正以下轉錄文字：今天天氣很好我們去公園走走"

# 從 stdin 管道輸入
echo "轉錄文字內容" | claude -p "請校正這段語音轉錄文字"

# 指定模型
claude -p "校正文字" --model haiku
claude -p "校正文字" --model sonnet
```

### 指定模型

```bash
claude -p "..." --model haiku     # claude-haiku-4-5 — 最快、最便宜
claude -p "..." --model sonnet    # claude-sonnet-4-6 — 平衡型
claude -p "..." --model opus      # claude-opus-4-6 — 最強但最貴
```

### 輸出格式控制

```bash
# 純文字（預設）
claude -p "..." --output-format text

# JSON（含 metadata：cost, duration, session_id）
claude -p "..." --output-format json

# 串流 JSON
claude -p "..." --output-format stream-json
```

### 結構化輸出（JSON Schema 驗證）

```bash
claude -p "校正並回傳結構化結果" \
  --output-format json \
  --json-schema '{"type":"object","properties":{"corrected":{"type":"string"},"changes":{"type":"array","items":{"type":"string"}}}}'
```

---

## 整合方案構想

### 方案 A：Shell Script 後處理（最簡單）

轉錄完成後，在 shell 層呼叫 `claude -p` 做校正：

```bash
#!/bin/bash
# 假設 ASR 輸出存在 /tmp/transcript.txt
TRANSCRIPT=$(cat /tmp/transcript.txt)
CORRECTED=$(echo "$TRANSCRIPT" | claude -p \
  "你是 VerbatimFlow 校正器。修正語音轉錄的錯字、標點和格式。
規則：保持原意、不增加內容、不改語言。只輸出修正後的文字。" \
  --model haiku \
  --output-format text)
echo "$CORRECTED"
```

### 方案 B：Swift Process 子程序呼叫

類似現有 Whisper/Qwen 的 Python subprocess 模式，在 Swift 中呼叫 `claude` CLI：

```swift
// 概念示意 — 類似現有 SpeechTranscriber 呼叫 Python 的模式
func correctWithClaude(text: String, model: String = "haiku") throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/local/bin/claude")
    process.arguments = ["-p", prompt, "--model", model, "--output-format", "text"]
    // ... pipe stdin/stdout ...
}
```

### 方案 C：批次校正腳本（離線使用）

```bash
# 對轉錄歷史批次校正
for f in ~/transcripts/*.txt; do
  cat "$f" | claude -p "校正此段語音轉錄" --model haiku > "${f%.txt}.corrected.txt"
done
```

---

## Haiku vs Sonnet 模型比較

| 維度 | Haiku | Sonnet |
|------|-------|--------|
| **延遲** | ~0.5-1.5 秒（估計） | ~1.5-4 秒（估計） |
| **成本** | 最低（約 Sonnet 的 1/10） | 中等 |
| **中文能力** | 良好，簡單校正足夠 | 優秀，複雜語境更好 |
| **上下文理解** | 基本 | 較強 |
| **指令遵循** | 良好 | 優秀 |
| **適合場景** | 簡單錯字、標點、格式修正 | 語意模糊處理、專業術語、複雜中英混合 |

### Haiku 適合的校正任務

- 基本標點修正（逗號、句號、問號）
- 明顯錯字修正
- 空格/格式正規化
- 簡單的語氣詞移除
- 中英文標點切換

### Sonnet 更適合的校正任務

- 上下文相關的同音字選擇（中文：「的/得/地」、「在/再」）
- 專業術語校正
- 複雜句子結構調整
- 中英混合語境中的語碼轉換修正
- 需要理解語意才能判斷的錯誤

---

## 優點

### 1. 整合極簡
- 不需要管理 API key（Claude Code 本身已認證）
- 不需要寫 HTTP 請求邏輯
- 一行 shell 指令即可呼叫
- 比起現有 ClarifyRewriter 的 HTTP 實作，程式碼量極少

### 2. 模型彈性
- `--model` 一個 flag 即可切換 Haiku/Sonnet/Opus
- 可根據場景動態選擇：簡單文字用 Haiku，複雜內容用 Sonnet
- 未來模型升級時自動受益，無需改程式碼

### 3. 結構化輸出
- `--json-schema` 可強制回傳結構化結果
- 可以要求模型同時回傳：校正文字 + 變更說明 + 信心分數
- 比純文字 API 回傳更容易程式化處理

### 4. 會話延續
- `--resume` 可延續先前 session
- 理論上可以建立「校正上下文」，讓後續校正參考先前的修正風格

### 5. 中文處理能力
- Claude 模型家族的中文理解力在同級模型中表現優秀
- 對中英混合文字的處理能力強
- 能理解台灣用語、簡繁差異

### 6. 工具使用能力
- `claude -p` 可搭配 `--allowedTools` 讓模型讀取 terminology 檔案
- 例如讓模型自己讀取 `terminology.txt` 來輔助校正

---

## 缺點與限制

### 1. 延遲是最大瓶頸
- **VerbatimFlow 的核心場景是即時聽寫**，使用者說完話到文字出現應在 1-2 秒內
- `claude -p` 每次呼叫是一個新的 **進程啟動**，包含：
  - CLI 初始化
  - 認證檢查
  - API 請求建立
  - 模型推理
  - 回應解析
- 即使是 Haiku，整個 round-trip 也預估需要 **1.5-3 秒**
- 加上原本的 ASR 延遲，總延遲可能達到 **3-6 秒**，對即時聽寫來說太慢
- 相比之下，現有的 regex TextGuard 幾乎是 0ms

### 2. 進程開銷
- 每次校正都要 spawn 一個新的 `claude` 子進程
- 不像 HTTP API 可以複用連線
- 在高頻率的語音輸入場景（每幾秒一次），進程啟動的開銷會累積
- 沒有連線池或 keep-alive 機制

### 3. 依賴 Claude Code 安裝
- 使用者必須已安裝 Claude Code CLI 且完成認證
- 增加了一個外部依賴，不像 OpenAI API 只需要一個 key
- Claude Code 的安裝/更新/認證流程比設定一個環境變數複雜得多
- 如果 Claude Code 未登入或 token 過期，校正會靜默失敗

### 4. 成本不透明
- Claude Code 的計費是 per-developer 月費或 API credit
- 每次校正的實際 token 消耗不如直接呼叫 API 那麼可控
- `claude -p` 會附帶 system prompt 和工具定義，增加額外 token 開銷
- 高頻使用（每分鐘多次校正）可能快速消耗額度

### 5. 無法精細控制 API 參數
- 無法直接設定 `temperature`（ClarifyRewriter 目前用 0.1）
- 無法設定 `max_tokens` 限制回應長度
- 無法控制 system prompt 的 token 消耗（claude -p 有自己的 system prompt）
- 對於轉錄校正這種需要高確定性（low temperature）的任務，缺乏控制是個問題

### 6. 不穩定的輸出格式
- 即使用 `--output-format text`，模型可能在回答前加上解釋文字
- 需要額外的 prompt engineering 確保只回傳校正文字
- `--json-schema` 可以緩解但增加 overhead

### 7. 離線不可用
- VerbatimFlow 支援 Apple Speech 和 Whisper 的離線模式
- `claude -p` 完全依賴網路，離線場景無法使用
- 對於純本地使用者是個退步

---

## 與現有 ClarifyRewriter 方案對比

| 維度 | ClarifyRewriter (HTTP API) | claude -p CLI |
|------|---------------------------|---------------|
| **延遲** | ~0.5-2s（HTTP 直連） | ~1.5-4s（進程啟動 + API） |
| **設定複雜度** | 中（需要 API key + env 檔） | 低（Claude Code 已認證） |
| **參數控制** | 完整（temperature, max_tokens 等） | 有限 |
| **模型選擇** | 任何 OpenAI/OpenRouter 模型 | Claude 模型家族 |
| **離線支援** | 否 | 否 |
| **程式碼量** | ~350 行 Swift | ~10 行 Shell 或 ~30 行 Swift |
| **錯誤處理** | 精細（HTTP status, JSON error） | 粗略（process exit code） |
| **成本控制** | 精確（per-token 計費） | 較模糊 |
| **批次處理** | 需要自行實作 | 天然支援（shell loop） |

---

## 建議

### 適合使用 `claude -p` 的場景

1. **離線批次校正**：轉錄完畢後，非即時地批次校正歷史轉錄
2. **開發/測試階段**：快速驗證 Claude 模型的校正品質，不需要寫整合程式碼
3. **腳本自動化**：CI/CD 中的轉錄品質檢查
4. **一次性校正任務**：手動校正大量歷史轉錄文件

### 不適合的場景

1. **即時聽寫校正**：延遲太高，無法達到即時體驗
2. **高頻呼叫**（每秒多次）：進程開銷累積
3. **需要精細 API 控制**的生產環境

### 如果要做即時校正，建議的替代方案

如果目標是用 Claude 模型做即時校正，更好的方式是：

1. **直接呼叫 Anthropic Messages API**：類似現有 ClarifyRewriter 的 HTTP 模式
   - 可精確控制 temperature、max_tokens
   - 延遲更低（省去 CLI 啟動開銷）
   - 可複用 HTTP 連線

2. **透過 OpenRouter 使用 Claude 模型**：
   - 現有 ClarifyRewriter 已支援 OpenRouter
   - 只需把 model 改為 `anthropic/claude-3-haiku` 或 `anthropic/claude-3.5-sonnet`
   - 零程式碼修改即可切換

### 推薦策略

```
即時校正 → Anthropic API 或 OpenRouter（HTTP 直連）
批次校正 → claude -p --model haiku（簡單腳本）
品質評估 → claude -p --model sonnet --output-format json（結構化分析）
```

---

## 快速驗證指令

如果想快速測試 Claude 模型的校正品質：

```bash
# Haiku — 快速校正
echo "今天天氣很好 我們去公園走走 嗯 然後買杯咖啡" | \
  claude -p "你是語音轉錄校正器。只修正標點和格式，保持原意。只輸出校正後文字。" \
  --model haiku

# Sonnet — 品質校正
echo "那個 我想說的是 VerbatimFlow 這個 app 它可以幫助我們做 dictation" | \
  claude -p "你是語音轉錄校正器。移除語氣詞，修正標點格式，保持原意和語言。只輸出校正後文字。" \
  --model sonnet

# 結構化輸出 — 同時拿到校正結果和變更說明
echo "嗯我今天要介紹一下我們的新功能" | \
  claude -p "校正此語音轉錄並說明變更" \
  --model sonnet \
  --output-format json
```

---

## 結論

`claude -p` 作為轉錄校正工具，最大的價值在於**快速驗證和批次處理**，而非即時校正。對 VerbatimFlow 的即時聽寫場景，直接呼叫 Anthropic API（或透過 OpenRouter）會是更適合的生產方案。但 `claude -p` 可以作為開發階段的品質基準測試工具，幫助確認 Claude 模型是否值得整合進生產流程。

Haiku 適合做為預設校正模型（成本低、速度快、品質足夠應付常見錯誤），Sonnet 則留給需要更深語意理解的複雜校正場景。
