# sherpa-onnx 標點模型遷移 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把 benchmark 的標點模型從 funasr (~1 GB) 換成 sherpa-onnx INT8 (72 MB)，重跑 benchmark 驗證品質。

**Architecture:** 直接替換 `PunctuationModel` 內部實作（funasr → sherpa-onnx），公開介面不變。模型檔放 `scripts/models/`，首次執行自動下載。先裸跑測英文是否被拆碎，再決定是否保留佔位符機制。

**Tech Stack:** sherpa-onnx, opencc-python-reimplemented, pytest

**設計文件:** `docs/plans/2026-03-04-sherpa-onnx-migration-design.md`

---

### Task 1: 安裝 sherpa-onnx 並驗證可用

**Files:**
- Modify: `.gitignore`

**Step 1: 安裝 sherpa-onnx**

Run: `pip install sherpa-onnx`
Expected: 安裝成功，無 PyTorch 依賴

**Step 2: 驗證 import**

Run: `python -c "import sherpa_onnx; print(sherpa_onnx.__version__)"`
Expected: 版本號輸出（如 1.12.28）

**Step 3: 加入 .gitignore**

在 `.gitignore` 的 `scripts/benchmark_results/` 後面加入：

```
# Punctuation model files
scripts/models/
```

**Step 4: Commit**

```bash
git add .gitignore
git commit -m "chore: add scripts/models/ to gitignore for sherpa-onnx model files"
```

---

### Task 2: 寫 PunctuationModel 的 unit tests（sherpa-onnx 版）

**Files:**
- Modify: `scripts/tests/test_benchmark_punctuation.py`

**Step 1: 重寫測試，mock 改為 sherpa_onnx**

把三個現有測試改為 mock `sherpa_onnx` 而非 `funasr`。sherpa-onnx 的 API 是 `OfflinePunctuation.add_punctuation(text) -> str`，不是 `AutoModel.generate(input=) -> [{"text": ...}]`。

```python
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import unittest.mock as mock


class TestPunctuationModel:
    def test_add_punctuation_calls_sherpa_and_opencc(self):
        """Verify PunctuationModel chains sherpa-onnx → OpenCC convert."""
        with mock.patch("benchmark_punctuation._ensure_model", return_value="/fake/model.onnx"), \
             mock.patch("benchmark_punctuation.sherpa_onnx") as MockSherpa, \
             mock.patch("benchmark_punctuation.OpenCC") as MockOpenCC:

            mock_punct = mock.MagicMock()
            mock_punct.add_punctuation.return_value = "今天天气很好，我们去散步。"
            MockSherpa.OfflinePunctuation.return_value = mock_punct

            mock_cc = mock.MagicMock()
            mock_cc.convert.return_value = "今天天氣很好，我們去散步。"
            MockOpenCC.return_value = mock_cc

            from benchmark_punctuation import PunctuationModel
            pm = PunctuationModel()
            result = pm.add_punctuation("今天天气很好我们去散步")

            assert result == "今天天氣很好，我們去散步。"
            mock_punct.add_punctuation.assert_called_once_with("今天天气很好我们去散步")
            MockOpenCC.assert_called_once_with("s2t")
            mock_cc.convert.assert_called_once_with("今天天气很好，我们去散步。")

    def test_add_punctuation_raw_returns_without_opencc(self):
        """Verify add_punctuation_raw returns sherpa-onnx output without OpenCC."""
        with mock.patch("benchmark_punctuation._ensure_model", return_value="/fake/model.onnx"), \
             mock.patch("benchmark_punctuation.sherpa_onnx") as MockSherpa, \
             mock.patch("benchmark_punctuation.OpenCC"):

            mock_punct = mock.MagicMock()
            mock_punct.add_punctuation.return_value = "今天天气很好，我们去散步。"
            MockSherpa.OfflinePunctuation.return_value = mock_punct

            from benchmark_punctuation import PunctuationModel
            pm = PunctuationModel()
            result = pm.add_punctuation_raw("今天天气很好我们去散步")

            assert result == "今天天气很好，我们去散步。"

    def test_elapsed_time_tracked(self):
        """Verify add_punctuation_timed returns elapsed time."""
        with mock.patch("benchmark_punctuation._ensure_model", return_value="/fake/model.onnx"), \
             mock.patch("benchmark_punctuation.sherpa_onnx") as MockSherpa, \
             mock.patch("benchmark_punctuation.OpenCC") as MockOpenCC:

            mock_punct = mock.MagicMock()
            mock_punct.add_punctuation.return_value = "測試。"
            MockSherpa.OfflinePunctuation.return_value = mock_punct

            mock_cc = mock.MagicMock()
            mock_cc.convert.return_value = "測試。"
            MockOpenCC.return_value = mock_cc

            from benchmark_punctuation import PunctuationModel
            pm = PunctuationModel()
            result, elapsed = pm.add_punctuation_timed("測試")

            assert result == "測試。"
            assert isinstance(elapsed, float)
            assert elapsed >= 0

    def test_ensure_model_called_on_init(self):
        """Verify _ensure_model is called during initialization."""
        with mock.patch("benchmark_punctuation._ensure_model", return_value="/fake/model.onnx") as mock_ensure, \
             mock.patch("benchmark_punctuation.sherpa_onnx"), \
             mock.patch("benchmark_punctuation.OpenCC"):

            from benchmark_punctuation import PunctuationModel
            PunctuationModel()

            mock_ensure.assert_called_once()
```

**Step 2: 跑測試確認失敗**

Run: `cd scripts && python -m pytest tests/test_benchmark_punctuation.py -v`
Expected: FAIL — `benchmark_punctuation` 仍在 import funasr

---

### Task 3: 實作 sherpa-onnx 版 PunctuationModel

**Files:**
- Modify: `scripts/benchmark_punctuation.py`

**Step 1: 替換完整實作**

```python
#!/usr/bin/env python3
"""sherpa-onnx CT-Transformer punctuation model wrapper for benchmark."""

import tarfile
import time
import urllib.request
from pathlib import Path

import sherpa_onnx
from opencc import OpenCC

MODEL_DIR = Path(__file__).parent / "models"
MODEL_NAME = "sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8"
MODEL_FILE = MODEL_DIR / MODEL_NAME / "model.int8.onnx"
DOWNLOAD_URL = (
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/"
    "punctuation-models/{}.tar.bz2"
)


def _ensure_model() -> Path:
    """Download and extract the punctuation model if not present."""
    if MODEL_FILE.exists():
        return MODEL_FILE
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    url = DOWNLOAD_URL.format(MODEL_NAME)
    archive_path = MODEL_DIR / f"{MODEL_NAME}.tar.bz2"
    print(f"Downloading punctuation model from {url} ...")
    urllib.request.urlretrieve(url, archive_path)
    print(f"Extracting to {MODEL_DIR} ...")
    with tarfile.open(archive_path, "r:bz2") as tar:
        tar.extractall(path=MODEL_DIR)
    archive_path.unlink()
    if not MODEL_FILE.exists():
        raise FileNotFoundError(f"Model file not found after extraction: {MODEL_FILE}")
    print(f"Model ready: {MODEL_FILE} ({MODEL_FILE.stat().st_size / 1e6:.0f} MB)")
    return MODEL_FILE


class PunctuationModel:
    """Wrapper for sherpa-onnx CT-Transformer punctuation restoration."""

    def __init__(self):
        model_path = str(_ensure_model())
        config = sherpa_onnx.OfflinePunctuationConfig(
            model=sherpa_onnx.OfflinePunctuationModelConfig(
                ct_transformer=model_path,
            ),
        )
        self.punct = sherpa_onnx.OfflinePunctuation(config)
        self.cc = OpenCC("s2t")

    def _run_bert(self, text: str) -> str:
        """Run punctuation model on text."""
        return self.punct.add_punctuation(text)

    def add_punctuation(self, text: str) -> str:
        """Add punctuation and convert to Traditional Chinese."""
        result = self._run_bert(text)
        return self.cc.convert(result)

    def add_punctuation_raw(self, text: str) -> str:
        """Add punctuation without OpenCC conversion."""
        return self._run_bert(text)

    def add_punctuation_timed(self, text: str) -> tuple[str, float]:
        """Add punctuation and return (result, elapsed_seconds)."""
        start = time.time()
        result = self.add_punctuation(text)
        elapsed = time.time() - start
        return result, round(elapsed, 3)
```

注意：先不加英文保護。`_run_bert` 直接呼叫 `self.punct.add_punctuation(text)`。

**Step 2: 跑 unit tests**

Run: `cd scripts && python -m pytest tests/test_benchmark_punctuation.py -v`
Expected: 4 tests PASS

**Step 3: 跑 scoring tests 確認介面相容**

Run: `cd scripts && python -m pytest tests/test_benchmark_scoring.py -v`
Expected: 全部 PASS（這些 tests 用 mock，不依賴具體 backend）

**Step 4: Commit**

```bash
git add scripts/benchmark_punctuation.py scripts/tests/test_benchmark_punctuation.py
git commit -m "feat: replace funasr with sherpa-onnx for punctuation model (72MB INT8)"
```

---

### Task 4: 跑 benchmark 並比較結果

**Files:**
- 無程式碼改動，只跑測試產出結果

**Step 1: 跑 bert-only benchmark**

Run: `cd scripts && python benchmark_llm.py --mode bert-only`
Expected: 自動下載模型（首次約 72 MB）→ 跑 20 test cases → 產出 JSON + Markdown

記錄加權總分，對比 funasr bert-only: **39.33**

**Step 2: 跑 bert+regex benchmark**

Run: `cd scripts && python benchmark_llm.py --mode bert+regex`
Expected: 跑 20 test cases → 產出 JSON + Markdown

記錄加權總分，對比 funasr bert+regex: **86.95**

**Step 3: 檢查英文處理品質**

手動檢查 bert-only 結果 JSON 中 t01-t05 的 output，這些 case 含大量英文：
- t01: `Quant 38B`, `Brice ASR`, `LIM Studio`, `M2X`
- t03: `Cloud Code`, `work flow`, `Comet`
- t05: `Git Hub`, `Open AI`

關鍵問題：英文有沒有被拆碎（如 `G it H ub`）？

- 若沒被拆碎 → Task 5（記錄結論）
- 若被拆碎 → Task 4a（加回英文保護）

**Step 4: 確認模型檔案大小**

Run: `du -sh scripts/models/`
Expected: ~72 MB

---

### Task 4a（條件性）: 加回英文保護機制

只在 Task 4 Step 3 確認英文被拆碎時才執行。

**Files:**
- Modify: `scripts/benchmark_punctuation.py`

**Step 1: 加回 `_protect_english` 和 `_restore_english`**

把原本的佔位符函式加回（不需修改，直接從 git history 複製）。修改 `_run_bert`：

```python
def _run_bert(self, text: str) -> str:
    """Run punctuation model with English protection."""
    protected, spans = _protect_english(text)
    result = self.punct.add_punctuation(protected)
    return _restore_english(result, spans)
```

**Step 2: 重跑 benchmark**

Run: `cd scripts && python benchmark_llm.py --mode bert-only bert+regex`

**Step 3: Commit**

```bash
git add scripts/benchmark_punctuation.py
git commit -m "fix: add English protection for sherpa-onnx punctuation model"
```

---

### Task 5: 記錄結果並更新文件

**Files:**
- Create: 更新 `docs/plans/2026-03-04-sherpa-onnx-migration-design.md` 結果段落

**Step 1: 在設計文件加入結果**

在設計文件末尾加入 `## 實測結果` 段落，包含：

- sherpa-onnx bert-only vs funasr bert-only 三維分數
- sherpa-onnx bert+regex vs funasr bert+regex 三維分數
- 英文保護：需要 / 不需要
- 模型檔案大小確認
- 結論：是否通過成功標準（bert+regex ≥ 80）

**Step 2: 更新全域 memory**

更新 `~/.claude/memory/funasr-punctuation-reference.md`，加入 sherpa-onnx 的實測數據。

**Step 3: Commit**

```bash
git add docs/plans/2026-03-04-sherpa-onnx-migration-design.md
git commit -m "docs: add sherpa-onnx benchmark results to design doc"
```
