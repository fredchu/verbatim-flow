# LLM ASR Post-Processing Benchmark 設計文件

> Date: 2026-03-03
> Branch: feat/breeze-asr
> Status: Approved

## 背景

VerbatimFlow 目前使用 LM Studio + Qwen3 8B (8-bit MLX) 做 ASR 後處理（術語校正、加標點符號）。實測發現模型對提示詞中術語替換表的遵從度不夠好——該替換的術語沒被替換，同時句子結構被過度改寫。

需要系統性地評估不同 MLX 模型在三個 ASR 後處理任務上的表現，找出最佳模型組合。

## 使用場景

1. **VerbatimFlow 聽寫**：短句（1-3 句，< 100 字），即時校正
2. **影片字幕轉錄**：長篇（5-10 句，數百到數千字），批次處理
3. **段落切分**：較長的聽寫內容按語義切分段落

## 方案選擇

- **方案 A（採用）**：單一提示詞 + 多模型橫評，自動化腳本評分
- 方案 B（備用）：多提示詞 × 多模型矩陣，若方案 A 發現模型對提示詞敏感度差異大則擴展
- 方案 C（未來）：BERT 標點模型 + LLM 術語校正兩層架構

## 測試資料集

JSON 格式，存放於 `scripts/benchmark_testcases.json`。

每個測試案例結構：

```json
{
  "id": "t01",
  "input": "ASR 原始輸出（含誤識別）",
  "expected": "人工標註的正確結果（含標點）",
  "terminology_corrections": ["錯誤詞→正確詞", ...],
  "type": "short | long"
}
```

- **short**（短句）：10-15 則，模擬聽寫場景
- **long**（長篇）：5 則，模擬字幕轉錄場景
- 來源：實際 ASR 誤識別案例（使用者實測收集）

## 評分指標

四個指標，前三個加權計算綜合分數：

### 1. 術語校正率（Terminology Recall）— 權重 40%

- 計算：`正確替換數 / 應替換數 × 100`
- 逐條檢查 `terminology_corrections` 中的正確術語是否出現在輸出中

### 2. 文字保留度（Text Preservation）— 權重 30%

- 將輸入和輸出都去掉標點符號和已知術語替換後，算字元級 edit distance
- 分數：`max(0, 100 - 多餘編輯字元數 × 5)`
- 衡量「過度改寫」程度，edit distance = 0 為滿分

### 3. 標點品質（Punctuation F1）— 權重 30%

- 以 expected 的標點位置為 gold standard
- 計算模型輸出的標點 precision / recall / F1
- 寬鬆模式：只看位置不區分標點類型
- 嚴格模式：位置 + 類型都要匹配

### 4. 速度（Throughput）— 不加權，記錄參考

- tokens/sec（從 API response usage 計算）
- 首 token 延遲（time to first token）

### 綜合分數

```
score = terminology × 0.4 + preservation × 0.3 + punctuation_f1 × 0.3
```

## 模型測試清單

硬體：M1 Max 32GB

### Qwen3 系列（主力）

| 模型 | 量化 | 記憶體估算 | 測試理由 |
|---|---|---|---|
| Qwen3-0.6B | 8-bit | ~0.5 GB | 速度基準線，最小模型能否勝任 |
| Qwen3-1.7B | 8-bit | ~1.2 GB | 輕量甜蜜點候選 |
| Qwen3-4B | 8-bit | ~2.5 GB | 研究指出 4B 是效能/品質最佳平衡 |
| Qwen3-4B | 4-bit | ~1.5 GB | 同模型不同量化對比 |
| Qwen3-8B | 8-bit | ~5 GB | 目前基準線 |
| Qwen3-8B | 4-bit | ~3 GB | 測 4-bit 是否犧牲指令遵從度 |

### 非 Qwen 對照組

| 模型 | 量化 | 記憶體估算 | 測試理由 |
|---|---|---|---|
| Gemma 3-4B | 8-bit | ~2.5 GB | Google 模型，中文能力對照 |
| Phi-4-mini (3.8B) | 8-bit | ~2.5 GB | 微軟模型，指令遵從度評價高 |

共 8 個模型組合 × 15-20 則測試案例 ≈ 120-160 次 API 呼叫。

## 腳本架構

```
scripts/
  benchmark_llm.py          # 主腳本
  benchmark_testcases.json  # 測試資料集
  benchmark_results/        # 輸出目錄
    results_YYYYMMDD_HHMMSS.json   # 原始結果（所有模型）
    report_YYYYMMDD_HHMMSS.md      # Markdown 比較報告
```

### 執行流程

1. 讀取 `benchmark_testcases.json`
2. 提示使用者確認 LM Studio 已載入模型，輸入模型名稱
3. 對每個測試案例發送 POST 到 `http://localhost:1234/v1/chat/completions`
4. 收集回應、計算四個指標
5. 存入 JSON + 產生 Markdown 比較表
6. 提示「切換下一個模型，按 Enter 繼續」，重複 2-5

### 提示詞（初始版本 v1）

```
你是標點與術語校正器。
規則：
- 只加標點符號（，。！？；：「」），不修改任何文字內容。
- 唯一例外：套用以下術語替換表，將語音誤識別的詞彙修正為正確寫法。
- 不刪字、不加字、不改寫、不潤飾、不合併語句。
- 使用全形標點符號。
- 術語替換：歐拉瑪 → Ollama｜Comet → Commit｜walk flow → workflow｜work flow → workflow｜偷坑 → token｜B肉 → BROLL｜逼肉 → BROLL｜Cloud Code → Claude Code｜Super power → Superpowers｜Super powers → Superpowers｜Brise ASR → Breeze ASR｜Bruce ASR → Breeze ASR｜Brice ASR → Breeze ASR｜Quint 3 → Qwen3｜Quant 3 → Qwen3｜Quant 38B → Qwen3 8B｜集聚 → 級距｜LIM Studio → LM Studio｜Emerald X → MLX｜M2X → MLX
- 僅輸出結果，不要解釋。 /no_think
```

提示詞硬編碼為常數，未來擴展方案 B 時改為支援多提示詞。

## 輸出格式

### Markdown 報告

```markdown
# LLM ASR Post-Processing Benchmark
Date: YYYY-MM-DD HH:MM
Prompt: v1

## 綜合排名
| # | 模型 | 術語(40%) | 保留度(30%) | 標點(30%) | 加權總分 | tok/s |
|---|---|---|---|---|---|---|
| 1 | ... | ... | ... | ... | ... | ... |

## 各案例明細
### t01: [案例描述]
- 輸入: ...
- 期望: ...
- [模型A]: ... ✓術語1 ✗術語2
- [模型B]: ... ✓術語1 ✓術語2
```

## 擴展路徑

1. **方案 B 擴展**：新增多種提示詞變體（few-shot、JSON 輸出、分步指令），測試矩陣從 8 模型擴展到 8 模型 × 3-4 提示詞
2. **方案 C 未來**：引入 BERT 標點模型（`punct_cap_seg_47_language`）做第一層，LLM 只負責術語校正和段落切分
3. **段落切分評估**：待術語和標點的最佳模型確定後，加入段落切分的測試案例和評分指標
