# 研究：Groq API 用於即時聽寫校正的可行性評估

> 日期：2026-03-02
> 狀態：研究筆記

## 背景

前一份研究（`research-cli-transcript-correction.md`）結論指出：`claude -p` 不適合即時校正，主要瓶頸是 CLI 進程啟動 + API 延遲過高。本研究評估 Groq API 作為即時聽寫校正方案的可行性。

Groq 使用自研的 **LPU（Language Processing Unit）** 晶片，專為推理設計，速度遠超 GPU 方案。

---

## Groq API 概要

### 基本資訊

- **Base URL:** `https://api.groq.com/openai/v1`
- **認證方式:** `Authorization: Bearer GROQ_API_KEY`
- **API 格式:** 完全 OpenAI 相容（相同的 request/response JSON schema）
- **Chat Completions Endpoint:** `POST /chat/completions`

### 與 VerbatimFlow 的相容性

Groq 的 API 與 OpenAI 完全相容，這代表現有 `ClarifyRewriter.swift` **幾乎不需要修改**就能支援 Groq。只需：

1. 在 `resolvedClarifyTransport()` 加一個 `case "groq":` 分支（~25 行 Swift）
2. 設定 `GROQ_API_KEY` 和 `VERBATIMFLOW_CLARIFY_PROVIDER=groq`
3. 其餘 HTTP 請求建構、回應解析、錯誤處理全部複用

---

## 可用模型與推薦

### 即時校正推薦模型

| 模型 | Model ID | 速度 | 成本 ($/M tokens) | 上下文 | 中文能力 | 推薦程度 |
|------|----------|------|-------------------|--------|----------|----------|
| **Qwen3 32B** | `qwen/qwen3-32b` | ~535 T/s | $0.29 in / $0.59 out | 131K | ★★★★★ | **首選** |
| Llama 3.1 8B | `llama-3.1-8b-instant` | ~560 T/s | $0.05 in / $0.08 out | 131K | ★★☆☆☆ | 英文場景 |
| Llama 3.3 70B | `llama-3.3-70b-versatile` | ~276 T/s | $0.59 in / $0.79 out | 131K | ★★★☆☆ | 英文複雜場景 |
| GPT-OSS 20B | `openai/gpt-oss-20b` | ~1000 T/s | $0.075 in / $0.30 out | 131K | ★★★☆☆ | 極速場景 |
| GPT-OSS 120B | `openai/gpt-oss-120b` | ~500 T/s | $0.15 in / $0.60 out | 131K | ★★★☆☆ | 品質優先 |

### 為什麼 Qwen3 32B 是首選

1. **中文第一設計**：Qwen 系列由阿里巴巴開發，中文是第一語言
2. **151,936 詞彙表**：比 Llama 的 32,000 大 5 倍，中文 tokenization 效率翻倍
3. **119 種語言**：完美支援中英混合場景（VerbatimFlow 的核心用途）
4. **535 T/s on Groq**：速度快且足夠
5. **Reasoning 可關閉**：設定 `reasoning_effort: "none"` 可避免不必要的推理開銷

### 成本估算

一段典型的語音轉錄校正（~50 中文字 ≈ ~100 tokens input + system prompt ~200 tokens，output ~100 tokens）：

| 模型 | 單次校正成本 | 每日 200 次校正 | 每月成本 |
|------|------------|----------------|---------|
| Qwen3 32B | ~$0.000146 | ~$0.029 | ~$0.87 |
| Llama 3.1 8B | ~$0.000023 | ~$0.005 | ~$0.14 |
| GPT-OSS 20B | ~$0.000053 | ~$0.011 | ~$0.32 |

**結論：成本極低，即使高頻使用每月不到 $1。**

---

## 速度分析 — 關鍵指標

### Groq vs 其他提供商

| 提供商 | 70B 模型吞吐量 | 8B 模型吞吐量 |
|--------|---------------|--------------|
| **Groq** | **276 T/s** | **877 T/s** |
| 一般 GPU 提供商 | 50-150 T/s | 200-400 T/s |
| OpenAI (gpt-4o-mini) | ~100-150 T/s | — |

### 即時校正延遲估算

一段 50 字中文校正的端到端延遲：

```
網路延遲 (HTTPS round-trip)  ≈  50-150ms（視地理位置）
TTFT (Time to First Token)    ≈  200-450ms
輸出生成 (~100 tokens)         ≈  100-200ms (Qwen3 @ 535 T/s)
─────────────────────────────────────────
預估總延遲                     ≈  350-800ms
```

**對比現有方案：**

| 方案 | 預估延遲 | 適合即時？ |
|------|---------|-----------|
| TextGuard (regex) | <1ms | ✅ |
| **Groq Qwen3 32B** | **~350-800ms** | **✅ 可接受** |
| Groq Llama 3.1 8B | ~300-600ms | ✅ 最快 |
| OpenAI gpt-4o-mini | ~500-2000ms | ⚠️ 邊緣 |
| `claude -p` CLI | ~1500-4000ms | ❌ 太慢 |

**Groq 的延遲在即時聽寫場景中是可接受的**，加上 ASR 延遲（Whisper ~1-2s），總體驗約 2-3 秒，與目前 OpenAI Clarify 模式相當甚至更快。

### TTFT 注意事項

- Groq 的 TTFT 會隨 input token 數量線性增長
- 100 tokens input → TTFT 快（~200ms）
- 10K tokens input → TTFT 明顯增加
- 對於轉錄校正（通常 <500 tokens），TTFT 不是問題

---

## Rate Limits

### Free Tier（免費，無需信用卡）

| 模型 | 大約限制 |
|------|---------|
| `qwen/qwen3-32b` | ~1,000 req/day, ~6,000 TPM |
| `llama-3.3-70b-versatile` | ~30 RPM, ~60,000 TPM, ~14,400 req/day |
| `llama-3.1-8b-instant` | ~30 RPM, ~131,000 TPM |

**Free Tier 對個人聽寫足夠嗎？**
- 每日 200 次校正 → 需要 ~200 req/day → ✅ Free Tier 足夠
- 每分鐘 burst ~5 次 → ✅ 在 30 RPM 限制內
- 超過限制回傳 HTTP 429，不會產生費用

### Developer Tier（付費）

- Rate limit 可達 Free Tier 的 **10 倍**
- 解鎖 Batch API（50% 折扣）
- 25% 成本折扣

---

## 整合方案

### 程式碼修改量評估

只需修改 **兩個檔案**，新增約 **30 行 Swift**：

#### 1. `ClarifyRewriter.swift` — 新增 `case "groq":` 分支

```swift
case "groq":
    let apiKey = resolvedSetting(
        key: "VERBATIMFLOW_CLARIFY_API_KEY",
        environment: environment,
        fileValues: fileValues
    ) ?? resolvedSetting(
        key: "GROQ_API_KEY",
        environment: environment,
        fileValues: fileValues
    )
    guard let apiKey, !apiKey.isEmpty else {
        throw AppError.openAIClarifyFailed(
            "GROQ_API_KEY is missing. Set GROQ_API_KEY or VERBATIMFLOW_CLARIFY_API_KEY."
        )
    }

    let rawBaseURL = resolvedSetting(
        key: "VERBATIMFLOW_CLARIFY_BASE_URL",
        environment: environment,
        fileValues: fileValues
    ) ?? "https://api.groq.com/openai/v1"

    return ClarifyTransportConfig(
        provider: "groq",
        model: configuredModel ?? "qwen/qwen3-32b",
        endpoint: try resolvedChatCompletionsEndpoint(
            rawBaseURL: rawBaseURL, allowInsecure: allowInsecure),
        apiKey: apiKey,
        extraHeaders: [],
        openRouterProviderSort: nil
    )
```

#### 2. `OpenAISettings.swift` — 更新預設模板

新增 `GROQ_API_KEY=` 和相關註解。

#### 不需修改的部分

- HTTP 請求建構 ✅（相同格式）
- 回應解析 ✅（相同 `choices[0].message.content`）
- 錯誤處理 ✅（相同 HTTP status codes）
- `performRequest()` ✅
- `resolvedChatCompletionsEndpoint()` ✅（正確 append `/chat/completions`）

### 設定方式

```bash
# ~/Library/Application Support/VerbatimFlow/openai.env
VERBATIMFLOW_CLARIFY_PROVIDER=groq
GROQ_API_KEY=gsk_xxxxxxxxxxxx
VERBATIMFLOW_OPENAI_CLARIFY_MODEL=qwen/qwen3-32b
```

---

## 優點

### 1. 速度 — 解決即時校正的核心瓶頸
- Groq LPU 推理速度是 GPU 提供商的 2-5 倍
- 預估 350-800ms 完成一次校正，加上 ASR 後總延遲約 2-3 秒
- 比 OpenAI API 快，遠比 `claude -p` 快

### 2. 整合成本極低
- OpenAI 相容 API，現有 ClarifyRewriter 架構直接複用
- ~30 行新增程式碼即可支援
- 不需要新的 HTTP 客戶端、JSON 解析器或錯誤處理

### 3. 中文校正品質
- Qwen3 32B 的中文能力在同級模型中頂尖
- 151K 詞彙表確保中文 tokenization 效率（少 token = 更便宜 + 更快）
- 原生支援中英混合文字

### 4. 成本極低
- 每次校正 < $0.0002
- 每月高頻使用 < $1
- Free Tier 免費試用，個人使用可能永久免費

### 5. 免費方案可用
- 無需信用卡即可開始使用
- 每日 ~1,000 次請求對個人聽寫綽綽有餘
- 降低使用門檻

### 6. 完整功能支援
- Streaming（可做 partial 校正預覽）
- JSON Mode / Structured Outputs（結構化校正結果）
- Tool Calling（可讓模型查詢 terminology dict）
- `reasoning_effort: "none"`（Qwen3 專屬，關閉推理節省延遲）

---

## 缺點與風險

### 1. 地理位置延遲
- Groq 資料中心主要在北美
- 從台灣/亞洲連線的網路延遲 ~100-200ms（比美國本地多 50-150ms）
- 這可能把 350-800ms 推到 500-1000ms
- **緩解：** 仍然比 OpenAI API 快或相當；Groq 推理速度的優勢可以補償網路延遲

### 2. Preview 模型穩定性
- `qwen/qwen3-32b` 目前標記為 **Preview**
- Preview 模型可能隨時下架或更改行為
- Production 模型（如 `llama-3.3-70b-versatile`）更穩定但中文較弱
- **緩解：** 在設定檔中指定模型 ID，切換方便；可設定 fallback 模型

### 3. Free Tier 限制
- 高頻使用（>30 RPM）會被 rate limit
- Token per minute 限制（Qwen3 只有 ~6,000 TPM）可能是瓶頸
- 多人使用場景不適合 Free Tier
- **緩解：** Developer Tier 提供 10x 提升，成本仍然很低

### 4. 離線不可用
- 和所有雲端 API 一樣，離線無法使用
- VerbatimFlow 支援 Apple Speech + Whisper 本地模式
- Groq 校正只能作為線上增強，不能取代本地 TextGuard
- **緩解：** 保持現有架構：TextGuard（本地）→ Groq（可選線上增強）

### 5. 供應商鎖定風險
- Groq 是相對小型的公司，長期穩定性未知
- LPU 晶片供應鏈是否持續充足是個問號
- **緩解：** API 是 OpenAI 相容的，切換到其他提供商（OpenAI、OpenRouter、Anthropic）只需改 URL 和 key

### 6. Qwen3 推理模式的干擾
- Qwen3 預設啟用 thinking mode，可能在校正前做不必要的推理
- 推理 token 會增加延遲 10-40%
- **緩解：** 設定 `reasoning_effort: "none"` 關閉推理；或在 system prompt 明確指示不要推理

---

## 與其他方案完整對比

| 維度 | TextGuard (本地) | OpenAI API | Groq API | `claude -p` |
|------|-----------------|------------|----------|-------------|
| **延遲** | <1ms | 500-2000ms | **350-800ms** | 1500-4000ms |
| **中文品質** | 基本（regex） | 好 | **優秀（Qwen3）** | 優秀 |
| **成本** | $0 | ~$0.001/次 | **~$0.0002/次** | 不透明 |
| **離線** | ✅ | ❌ | ❌ | ❌ |
| **整合難度** | 已完成 | 已完成 | **~30 行 Swift** | 需重構 |
| **參數控制** | N/A | 完整 | 完整 | 有限 |
| **免費方案** | ✅ | ❌ | **✅** | 需訂閱 |
| **適合即時** | ✅ | ⚠️ | **✅** | ❌ |

---

## 建議

### 推薦整合策略

```
1. 新增 Groq provider → ClarifyRewriter.swift（~30 行）
2. 預設模型 → qwen/qwen3-32b（中文最佳）
3. 關閉推理 → reasoning_effort: "none"（減少延遲）
4. 保持 fallback → TextGuard regex 作為離線/失敗 fallback
5. 可選 streaming → 校正結果即時顯示
```

### 建議的模型選擇策略

| 使用情境 | 推薦模型 | 理由 |
|---------|---------|------|
| 中文/中英混合聽寫 | `qwen/qwen3-32b` | 中文最強，速度夠快 |
| 純英文聽寫 | `llama-3.1-8b-instant` | 最快最便宜 |
| 複雜英文（專業術語） | `llama-3.3-70b-versatile` | 品質更高 |
| 極速場景 | `openai/gpt-oss-20b` | 1000+ T/s |

### 快速驗證方式

```bash
# 用 curl 直接測試 Groq Qwen3 校正效果
curl -s https://api.groq.com/openai/v1/chat/completions \
  -H "Authorization: Bearer $GROQ_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen/qwen3-32b",
    "temperature": 0.1,
    "messages": [
      {"role": "system", "content": "你是 VerbatimFlow 校正器。修正語音轉錄的錯字、標點和格式。規則：保持原意、不增加內容、不改語言。只輸出修正後的文字。"},
      {"role": "user", "content": "locale=zh-Hant\n\n嗯今天我想跟大家介紹一下 VerbatimFlow 這個 app 它可以幫助我們做語音輸入然後直接打字到任何應用程式裡面"}
    ]
  }' | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])"
```

---

## 結論

**Groq API 是目前最適合 VerbatimFlow 即時校正的方案。** 原因：

1. **速度夠快**：350-800ms 延遲在即時聽寫場景可接受
2. **中文品質好**：Qwen3 32B 的中文能力頂尖
3. **整合極簡**：OpenAI 相容 API，現有架構直接複用，~30 行新程式碼
4. **成本極低**：Free Tier 可能完全免費；付費也 <$1/月
5. **風險可控**：API 相容標準格式，隨時可切換提供商

建議作為下一步實作：在 ClarifyRewriter 新增 Groq provider 支援，以 `qwen/qwen3-32b` 為預設校正模型。
