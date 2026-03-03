# 兩層 ASR 後處理架構設計

> Date: 2026-03-04
> Branch: feat/breeze-asr
> Status: Approved
> 前置：docs/plans/2026-03-03-llm-benchmark-design.md（方案 C）

## 背景

Plan A/B benchmark 結果顯示，小型本地 LLM 同時處理「標點插入」和「術語校正」時存在根本性 trade-off：

- **v1 prompt**（最佳）：加權總分 70.4，術語 66.4 / 保留度 86.8 / 標點 59.4
- 強化術語的 prompt（v2/v3）：術語提升到 84-87，但保留度暴跌到 7-40

根本原因：小模型無法同時遵從「加標點」和「只改術語不改文字」兩個互相矛盾的指令。

## 方案

分離關注點：**專門的標點模型處理標點，LLM 或 Regex 只做術語替換**。

## 架構

```
ASR 原始文字（無標點、有術語錯誤）
    ↓
[Layer 1] FunASR CT-Transformer (ONNX INT8, 72MB)
    → 加入中文標點符號（，。？、）
    → 輸出：簡體中文 + 標點
    ↓
[Layer 1.5] OpenCC s2t
    → 簡體轉繁體
    ↓
[Layer 2a] Regex 術語替換
    → 用 TERMINOLOGY_TABLE 做精確字串替換
    → 零延遲、100% 準確
    ↓
[Layer 2b] LLM 術語校正（可選）
    → 簡化提示詞：只做術語替換，不動標點和文字
    → 處理 Regex 漏掉的模糊匹配
    ↓
輸出：繁體中文 + 標點 + 正確術語
```

## 標點模型：FunASR CT-Transformer

- 來源：阿里達摩院 FunASR
- 模型：`ct-punc`（CT-Transformer, punc_ct-transformer_cn-en-common-vocab471067-large）
- 格式：ONNX INT8（72 MB）
- 推理延遲：<15ms
- 中文專用，支援中英混合
- 內建去語氣詞功能
- 輸出簡體中文，需搭配 OpenCC 轉繁

### 安裝方式

```bash
# 使用 funasr 套件（API 最簡單）
pip install funasr onnxruntime

# 備選：sherpa-onnx（純 ONNX，無 PyTorch 依賴）
pip install sherpa-onnx
```

### 使用方式

```python
from funasr import AutoModel
model = AutoModel(model="ct-punc", model_revision="v2.0.4")
result = model.generate(input="今天天氣很好我們去散步")
# → "今天天氣很好，我們去散步。"
```

## LLM 術語專用提示詞

```
你是術語校正器。
規則：
- 只替換以下術語表中的錯誤詞彙，不修改任何其他文字。
- 不加字、不刪字、不改標點符號、不改寫句子。
- 術語替換表：
  歐拉瑪 → Ollama
  Comet → Commit
  ...（完整術語表）
- 僅輸出結果，不要解釋。 /no_think
```

關鍵差異：明確禁止修改標點符號，因為標點已由 BERT 處理。

## Benchmark 測試矩陣

| 模式 | Layer 1 (標點) | Layer 2 (術語) | 目的 |
|------|---------------|---------------|------|
| `llm-only` | LLM（v1 prompt） | LLM（v1 prompt） | baseline |
| `bert-only` | FunASR CT | 無 | 純 BERT 標點效果 |
| `bert+regex` | FunASR CT + OpenCC | Regex 字典 | 最輕量組合 |
| `bert+llm` | FunASR CT + OpenCC | LLM（術語專用 prompt） | 推薦方案 |

## 腳本架構

```
scripts/
  benchmark_llm.py              # 修改：加入 --mode 參數支援四種模式
  benchmark_punctuation.py      # 新增：FunASR 標點模組
  benchmark_testcases.json      # 不變
  benchmark_results/            # 輸出
```

### benchmark_punctuation.py

```python
class PunctuationModel:
    def __init__(self):
        self.model = AutoModel(model="ct-punc", model_revision="v2.0.4")
        self.cc = OpenCC('s2t')

    def add_punctuation(self, text: str) -> str:
        result = self.model.generate(input=text)
        punctuated = result[0]["text"]
        return self.cc.convert(punctuated)
```

### benchmark_llm.py 新增 --mode

```
--mode llm-only     # 原本的單層 LLM（baseline）
--mode bert-only    # 只跑 FunASR 標點
--mode bert+regex   # BERT 標點 + Regex 術語替換
--mode bert+llm     # BERT 標點 + LLM 術語校正
--mode all          # 跑全部模式
```

### Regex 術語替換

```python
def apply_terminology_regex(text: str) -> str:
    for line in TERMINOLOGY_TABLE.strip().split("\n"):
        wrong, correct = line.split("→", 1)
        text = text.replace(wrong.strip(), correct.strip())
    return text
```

## 評分

四種模式使用同一組評分函式（score_terminology, score_preservation, score_punctuation），加權公式不變：

```
score = terminology × 0.4 + preservation × 0.3 + punctuation_f1 × 0.3
```

## 預期結果

- `bert+regex`：標點 F1 大幅提升（BERT 專精），術語 100%（精確匹配），保留度接近 100%
- `bert+llm`：標點同上，術語可能更高（模糊匹配），但保留度可能略降
- 若 `bert+regex` 已經夠好，就不需要 LLM 層
