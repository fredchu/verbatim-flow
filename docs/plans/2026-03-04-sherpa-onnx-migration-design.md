# sherpa-onnx 標點模型遷移設計

> Date: 2026-03-04
> Branch: feat/breeze-asr
> Status: Approved
> 前置：docs/plans/2026-03-04-two-layer-asr-design.md

## 背景

FunASR CT-Transformer 標點模型效果好（bert+regex 加權 87.0），但 PyTorch 版模型約 1 GB，對聽寫轉錄桌面應用來說太大。sherpa-onnx 提供同一模型的 ONNX INT8 版本，僅 72 MB。

## 目標

把 `scripts/benchmark_punctuation.py` 的 PunctuationModel 從 funasr 換成 sherpa-onnx，重跑 benchmark 驗證品質差異。

## 範圍

- 只改 benchmark 腳本，不動 production code
- 不整合進 Swift app

## 改動範圍

| 檔案 | 改動 |
|------|------|
| `scripts/benchmark_punctuation.py` | 替換 `__init__` 和 `_run_bert` 內部實作 |
| `scripts/tests/test_benchmark_punctuation.py` | mock 目標從 `funasr.AutoModel` 改成 `sherpa_onnx` |
| `.gitignore` | 加入 `scripts/models/` |

`benchmark_llm.py` 和 `test_benchmark_scoring.py` 不需要改。

## PunctuationModel 新實作

```python
import sherpa_onnx
from opencc import OpenCC

MODEL_DIR = Path(__file__).parent / "models"
MODEL_NAME = "sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8"
MODEL_FILE = MODEL_DIR / MODEL_NAME / "model.int8.onnx"
DOWNLOAD_URL = "https://github.com/k2-fsa/sherpa-onnx/releases/download/punctuation-models/{}.tar.bz2"

class PunctuationModel:
    def __init__(self):
        model_path = str(_ensure_model())
        config = sherpa_onnx.OfflinePunctuationConfig(
            model=sherpa_onnx.OfflinePunctuationModelConfig(
                ct_transformer=model_path
            ),
        )
        self.punct = sherpa_onnx.OfflinePunctuation(config)
        self.cc = OpenCC("s2t")

    def _run_bert(self, text: str) -> str:
        return self.punct.add_punctuation(text)
```

## 自動下載邏輯

```python
def _ensure_model() -> Path:
    if MODEL_FILE.exists():
        return MODEL_FILE
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    url = DOWNLOAD_URL.format(MODEL_NAME)
    # 下載 tar.bz2 → 解壓到 MODEL_DIR
    return MODEL_FILE
```

## 英文保護策略

- 第一輪：不加英文保護，裸跑 benchmark
- 對比 funasr 結果（特別看 t01-t03 英文密集 case）
- 若 sherpa-onnx 也拆碎英文 → 加回佔位符機制
- 若 sherpa-onnx 沒問題 → 刪除佔位符程式碼

## Benchmark 流程

1. `pip install sherpa-onnx`
2. 跑 `python benchmark_llm.py --mode bert-only bert+regex`
3. 產出新的 JSON 結果到 `benchmark_results/`
4. 與現有 funasr 結果比較：
   - `results_bert-only_20260304_010524.json`（funasr bert-only: 39.33）
   - `results_bert+regex_20260304_011612.json`（funasr bert+regex: 86.95）

## 成功標準

- sherpa-onnx bert+regex 加權 ≥ 80（funasr 是 87）
- 模型檔 ≤ 100 MB
- 若品質 < 75，結論為「品質不足以替換」，記錄於文件

## 模型資訊

| 項目 | funasr (現有) | sherpa-onnx (目標) |
|------|---------------|-------------------|
| 模型 | ct-punc v2.0.4 | ct-transformer zh-en vocab272727 INT8 |
| 大小 | ~1 GB (PyTorch) | 72 MB (ONNX INT8) |
| 詞表 | vocab471067 | vocab272727 |
| API | `AutoModel.generate(input=)` | `OfflinePunctuation.add_punctuation()` |
| 依賴 | funasr, torch | sherpa-onnx |

## 實測結果（2026-03-04）

### 成功標準驗證

| 標準 | 目標 | 實測 | 結果 |
|------|------|------|------|
| bert+regex 加權 | ≥ 80 | **87.20** | PASS |
| 模型檔大小 | ≤ 100 MB | **76 MB** (85 MB 含資料夾) | PASS |

### 詳細比較

| 維度 | funasr (1 GB) | sherpa-onnx (76 MB) | 差異 |
|------|---------------|---------------------|------|
| bert+regex 加權 | 86.95 | **87.20** | +0.25 |
| 術語召回率 | 100% | 100% | 持平 |
| 文字保留度 | 72.0% | 72.0% | 持平 |
| 標點 F1 | 84.5% | **85.45%** | +0.95 |
| bert-only 加權 | 39.33 | **49.50** | +10.17 |
| 推理速度 | 350-1250 ms | **3-20 ms** | ~100x 快 |
| 模型大小 | ~1 GB | **76 MB** | -92% |
| 英文保護 | 需要佔位符 | **不需要** | 簡化程式碼 |

### 英文處理

sherpa-onnx **不會拆碎英文**。測試案例 t01-t05 的英文序列（如 `Quant 38B`、`Brice ASR`、`LIM Studio`、`Cloud Code`、`Git Hub`）全部保持完整，無需 CJK 佔位符機制。

### 結論

sherpa-onnx 完勝：品質相同甚至略好（+0.25）、推理快 100 倍、模型小 92%、不需要英文保護。正式替換 funasr。
