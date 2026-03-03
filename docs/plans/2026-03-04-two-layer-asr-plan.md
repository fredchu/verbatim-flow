# Two-Layer ASR Post-Processing Benchmark Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add BERT punctuation + Regex/LLM terminology two-layer pipeline to the benchmark tool and compare against single-layer LLM baseline.

**Architecture:** FunASR CT-Transformer handles punctuation insertion (Layer 1), then OpenCC converts to Traditional Chinese, then either Regex dictionary or a terminology-only LLM prompt handles term correction (Layer 2). All four modes share the same scoring functions.

**Tech Stack:** Python 3, funasr, opencc-python-reimplemented (already installed), onnxruntime, pytest

---

### Task 1: Install FunASR and create PunctuationModel

**Files:**
- Create: `scripts/benchmark_punctuation.py`
- Create: `scripts/tests/test_benchmark_punctuation.py`

**Step 1: Install funasr into the project venv**

Run:
```bash
apps/mac-client/python/.venv/bin/pip install funasr
```

Expected: Installs successfully. `torch` is already in the venv so no heavy download.

**Step 2: Write the failing tests**

File: `scripts/tests/test_benchmark_punctuation.py`

```python
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import unittest.mock as mock


class TestPunctuationModel:
    def test_add_punctuation_calls_funasr_and_opencc(self):
        """Verify PunctuationModel chains FunASR generate → OpenCC convert."""
        with mock.patch("benchmark_punctuation.AutoModel") as MockAutoModel, \
             mock.patch("benchmark_punctuation.OpenCC") as MockOpenCC:

            mock_model = mock.MagicMock()
            mock_model.generate.return_value = [{"text": "今天天气很好，我们去散步。"}]
            MockAutoModel.return_value = mock_model

            mock_cc = mock.MagicMock()
            mock_cc.convert.return_value = "今天天氣很好，我們去散步。"
            MockOpenCC.return_value = mock_cc

            from benchmark_punctuation import PunctuationModel
            pm = PunctuationModel()
            result = pm.add_punctuation("今天天气很好我们去散步")

            assert result == "今天天氣很好，我們去散步。"
            mock_model.generate.assert_called_once_with(input="今天天气很好我们去散步")
            MockOpenCC.assert_called_once_with("s2t")
            mock_cc.convert.assert_called_once_with("今天天气很好，我们去散步。")

    def test_add_punctuation_raw_returns_without_opencc(self):
        """Verify add_punctuation_raw returns FunASR output without OpenCC."""
        with mock.patch("benchmark_punctuation.AutoModel") as MockAutoModel, \
             mock.patch("benchmark_punctuation.OpenCC"):

            mock_model = mock.MagicMock()
            mock_model.generate.return_value = [{"text": "今天天气很好，我们去散步。"}]
            MockAutoModel.return_value = mock_model

            from benchmark_punctuation import PunctuationModel
            pm = PunctuationModel()
            result = pm.add_punctuation_raw("今天天气很好我们去散步")

            assert result == "今天天气很好，我们去散步。"

    def test_elapsed_time_tracked(self):
        """Verify add_punctuation returns elapsed time."""
        with mock.patch("benchmark_punctuation.AutoModel") as MockAutoModel, \
             mock.patch("benchmark_punctuation.OpenCC") as MockOpenCC:

            mock_model = mock.MagicMock()
            mock_model.generate.return_value = [{"text": "測試。"}]
            MockAutoModel.return_value = mock_model

            mock_cc = mock.MagicMock()
            mock_cc.convert.return_value = "測試。"
            MockOpenCC.return_value = mock_cc

            from benchmark_punctuation import PunctuationModel
            pm = PunctuationModel()
            result, elapsed = pm.add_punctuation_timed("測試")

            assert result == "測試。"
            assert isinstance(elapsed, float)
            assert elapsed >= 0
```

**Step 3: Run tests to verify they fail**

Run: `apps/mac-client/python/.venv/bin/python -m pytest scripts/tests/test_benchmark_punctuation.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'benchmark_punctuation'`

**Step 4: Write minimal implementation**

File: `scripts/benchmark_punctuation.py`

```python
#!/usr/bin/env python3
"""FunASR CT-Transformer punctuation model wrapper for benchmark."""

import time

from funasr import AutoModel
from opencc import OpenCC


class PunctuationModel:
    """Wrapper for FunASR CT-Transformer punctuation restoration."""

    def __init__(self):
        self.model = AutoModel(model="ct-punc", model_revision="v2.0.4")
        self.cc = OpenCC("s2t")

    def add_punctuation(self, text: str) -> str:
        """Add punctuation and convert to Traditional Chinese."""
        result = self.model.generate(input=text)
        punctuated = result[0]["text"]
        return self.cc.convert(punctuated)

    def add_punctuation_raw(self, text: str) -> str:
        """Add punctuation without OpenCC conversion."""
        result = self.model.generate(input=text)
        return result[0]["text"]

    def add_punctuation_timed(self, text: str) -> tuple[str, float]:
        """Add punctuation and return (result, elapsed_seconds)."""
        start = time.time()
        result = self.add_punctuation(text)
        elapsed = time.time() - start
        return result, round(elapsed, 3)
```

**Step 5: Run tests to verify they pass**

Run: `apps/mac-client/python/.venv/bin/python -m pytest scripts/tests/test_benchmark_punctuation.py -v`
Expected: 3 passed

**Step 6: Commit**

```bash
git add scripts/benchmark_punctuation.py scripts/tests/test_benchmark_punctuation.py
git commit -m "feat: add PunctuationModel wrapper for FunASR CT-Transformer"
```

---

### Task 2: Add apply_terminology_regex() function

**Files:**
- Modify: `scripts/benchmark_llm.py` (add function after `TERMINOLOGY_TABLE`)
- Modify: `scripts/tests/test_benchmark_scoring.py` (add test class)

**Step 1: Write the failing tests**

Append to `scripts/tests/test_benchmark_scoring.py`:

```python
from benchmark_llm import apply_terminology_regex

class TestTerminologyRegex:
    def test_single_replacement(self):
        result = apply_terminology_regex("使用歐拉瑪來跑模型")
        assert result == "使用Ollama來跑模型"

    def test_multiple_replacements(self):
        result = apply_terminology_regex("Cloud Code的work flow可以自動Comet")
        assert result == "Claude Code的workflow可以自動Commit"

    def test_no_match_unchanged(self):
        result = apply_terminology_regex("今天天氣很好")
        assert result == "今天天氣很好"

    def test_all_table_entries_applied(self):
        # Verify a few specific entries from the table
        assert "Ollama" in apply_terminology_regex("歐拉瑪")
        assert "BROLL" in apply_terminology_regex("B肉")
        assert "BROLL" in apply_terminology_regex("逼肉")
        assert "token" in apply_terminology_regex("偷坑")
        assert "級距" in apply_terminology_regex("集聚")
        assert "MLX" in apply_terminology_regex("Emerald X")
        assert "MLX" in apply_terminology_regex("M2X")
```

**Step 2: Run tests to verify they fail**

Run: `apps/mac-client/python/.venv/bin/python -m pytest scripts/tests/test_benchmark_scoring.py::TestTerminologyRegex -v`
Expected: FAIL — `ImportError: cannot import name 'apply_terminology_regex'`

**Step 3: Write minimal implementation**

Add to `scripts/benchmark_llm.py` after `TERMINOLOGY_TABLE` (around line 41):

```python
def apply_terminology_regex(text: str) -> str:
    """Apply terminology corrections using string replacement."""
    result = text
    for line in TERMINOLOGY_TABLE.strip().split("\n"):
        wrong, correct = line.split("→", 1)
        result = result.replace(wrong.strip(), correct.strip())
    return result
```

**Step 4: Run tests to verify they pass**

Run: `apps/mac-client/python/.venv/bin/python -m pytest scripts/tests/test_benchmark_scoring.py::TestTerminologyRegex -v`
Expected: 4 passed

Also run all existing tests to verify no regressions:
Run: `apps/mac-client/python/.venv/bin/python -m pytest scripts/tests/test_benchmark_scoring.py -v`
Expected: 18 passed (14 existing + 4 new)

**Step 5: Commit**

```bash
git add scripts/benchmark_llm.py scripts/tests/test_benchmark_scoring.py
git commit -m "feat: add apply_terminology_regex() for dictionary-based term replacement"
```

---

### Task 3: Add v5-term-only prompt and run_two_layer_benchmark()

**Files:**
- Modify: `scripts/benchmark_llm.py` (add prompt, add function)
- Modify: `scripts/tests/test_benchmark_scoring.py` (add tests)

**Step 1: Add v5-term-only prompt to PROMPTS dict**

Add to `PROMPTS` dict in `scripts/benchmark_llm.py`:

```python
    "v5-term-only": f"""你是術語校正器。
規則：
- 只替換以下術語表中的錯誤詞彙，不修改任何其他文字。
- 不加字、不刪字、不改標點符號、不改寫句子。
- 術語替換表：
{TERMINOLOGY_TABLE}
- 僅輸出結果，不要解釋。 /no_think""",
```

**Step 2: Write the failing tests for run_two_layer_benchmark**

Append to `scripts/tests/test_benchmark_scoring.py`:

```python
from benchmark_llm import run_two_layer_benchmark, PROMPTS

class TestTwoLayerBenchmark:
    def test_bert_only_mode(self):
        """Verify bert-only mode calls PunctuationModel and scores output."""
        import unittest.mock as mock

        mock_punc = mock.MagicMock()
        mock_punc.add_punctuation_timed.return_value = ("今天天氣很好，我們去散步。", 0.01)

        testcases = [{
            "id": "t99",
            "input": "今天天氣很好我們去散步",
            "expected": "今天天氣很好，我們去散步。",
            "terminology_corrections": [],
            "terminology_pairs": [],
            "type": "short",
        }]

        with mock.patch("builtins.open", mock.mock_open(read_data=json.dumps(testcases))):
            result = run_two_layer_benchmark(
                "fake_path.json", mode="bert-only", punc_model=mock_punc,
            )

        assert result["avg_punctuation_f1"] > 0
        assert len(result["cases"]) == 1
        mock_punc.add_punctuation_timed.assert_called_once()

    def test_bert_regex_mode(self):
        """Verify bert+regex applies both punctuation and terminology."""
        import unittest.mock as mock

        mock_punc = mock.MagicMock()
        mock_punc.add_punctuation_timed.return_value = ("使用歐拉瑪來跑模型。", 0.01)

        testcases = [{
            "id": "t99",
            "input": "使用歐拉瑪來跑模型",
            "expected": "使用 Ollama 來跑模型。",
            "terminology_corrections": ["Ollama"],
            "terminology_pairs": ["歐拉瑪→Ollama"],
            "type": "short",
        }]

        with mock.patch("builtins.open", mock.mock_open(read_data=json.dumps(testcases))):
            result = run_two_layer_benchmark(
                "fake_path.json", mode="bert+regex", punc_model=mock_punc,
            )

        assert result["avg_terminology"] == 100.0
        assert result["cases"][0]["output"] == "使用Ollama來跑模型。"
```

**Step 3: Run tests to verify they fail**

Run: `apps/mac-client/python/.venv/bin/python -m pytest scripts/tests/test_benchmark_scoring.py::TestTwoLayerBenchmark -v`
Expected: FAIL — `ImportError: cannot import name 'run_two_layer_benchmark'`

**Step 4: Write minimal implementation**

Add to `scripts/benchmark_llm.py` (after `run_benchmark` function):

```python
def run_two_layer_benchmark(
    testcases_path: str,
    mode: str,
    punc_model=None,
    model: str = "",
    base_url: str = LM_STUDIO_DEFAULT_URL,
) -> dict:
    """Run benchmark with two-layer pipeline (BERT punctuation + terminology)."""
    with open(testcases_path) as f:
        testcases = json.load(f)

    cases = []
    for tc in testcases:
        print(f"  [{tc['id']}] {tc['input'][:40]}...")

        # Layer 1: BERT punctuation + OpenCC
        punctuated, elapsed = punc_model.add_punctuation_timed(tc["input"])

        # Layer 2: terminology correction
        if mode == "bert-only":
            output = punctuated
        elif mode == "bert+regex":
            output = apply_terminology_regex(punctuated)
        elif mode == "bert+llm":
            llm_result = call_llm(
                punctuated, model=model, base_url=base_url,
                prompt_key="v5-term-only",
            )
            output = llm_result["content"]
            elapsed += llm_result["elapsed_s"]
        else:
            raise ValueError(f"Unknown mode: {mode}")

        term_score = score_terminology(output, tc["terminology_corrections"])
        pres_score = score_preservation(
            tc["input"], output, tc.get("terminology_pairs", []),
        )
        prec, rec, f1 = score_punctuation(tc["expected"], output)
        weighted = term_score * 0.4 + pres_score * 0.3 + f1 * 0.3

        term_detail = [
            (term, term in output)
            for term in tc["terminology_corrections"]
        ]

        cases.append({
            "id": tc["id"],
            "type": tc["type"],
            "input": tc["input"],
            "expected": tc["expected"],
            "output": output,
            "terminology_score": term_score,
            "preservation_score": pres_score,
            "punctuation_precision": prec,
            "punctuation_recall": rec,
            "punctuation_f1": f1,
            "weighted_score": round(weighted, 2),
            "tokens_per_sec": 0,
            "elapsed_s": elapsed,
            "terminology_detail": term_detail,
        })

        status = "✓" if term_score == 100 else f"術語:{term_score:.0f}"
        print(f"         → {status} | 保留:{pres_score:.0f} | 標點F1:{f1:.0f} | {elapsed:.3f}s")

    avg = lambda key: round(sum(c[key] for c in cases) / len(cases), 2)

    return {
        "cases": cases,
        "avg_terminology": avg("terminology_score"),
        "avg_preservation": avg("preservation_score"),
        "avg_punctuation_f1": avg("punctuation_f1"),
        "avg_weighted": avg("weighted_score"),
        "avg_tokens_per_sec": 0,
    }
```

**Step 5: Run tests to verify they pass**

Run: `apps/mac-client/python/.venv/bin/python -m pytest scripts/tests/test_benchmark_scoring.py -v`
Expected: All passed (previous + 2 new)

**Step 6: Commit**

```bash
git add scripts/benchmark_llm.py scripts/tests/test_benchmark_scoring.py
git commit -m "feat: add v5-term-only prompt and run_two_layer_benchmark()"
```

---

### Task 4: Add --mode CLI parameter to main()

**Files:**
- Modify: `scripts/benchmark_llm.py` (update `main()`)

**Step 1: Update main() to support --mode**

Replace the `main()` function in `scripts/benchmark_llm.py`:

```python
MODES = ["llm-only", "bert-only", "bert+regex", "bert+llm"]


def main():
    parser = argparse.ArgumentParser(description="LLM ASR Post-Processing Benchmark")
    parser.add_argument(
        "--mode", nargs="+",
        choices=MODES + ["all"],
        default=["llm-only"],
        help="Pipeline modes to test (default: llm-only)",
    )
    parser.add_argument(
        "--models", nargs="+",
        help="Model IDs to test for LLM modes (default: all in DEFAULT_MODELS)",
    )
    parser.add_argument(
        "--prompt", nargs="+",
        choices=list(PROMPTS.keys()) + ["all"],
        default=[DEFAULT_PROMPT],
        help=f"Prompt variants for llm-only mode (default: {DEFAULT_PROMPT})",
    )
    parser.add_argument(
        "--url", default=LM_STUDIO_DEFAULT_URL,
        help=f"LM Studio API URL (default: {LM_STUDIO_DEFAULT_URL})",
    )
    args = parser.parse_args()

    models = args.models or DEFAULT_MODELS
    prompts = list(PROMPTS.keys()) if "all" in args.prompt else args.prompt
    modes = MODES if "all" in args.mode else args.mode

    testcases_path = Path(__file__).parent / "benchmark_testcases.json"
    output_dir = Path(__file__).parent / "benchmark_results"
    output_dir.mkdir(exist_ok=True)

    if not testcases_path.exists():
        print(f"Error: {testcases_path} not found")
        return

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    print("=" * 60)
    print("LLM ASR Post-Processing Benchmark")
    print("=" * 60)
    print(f"Test cases: {testcases_path}")
    print(f"Modes: {', '.join(modes)}")
    print()

    # Initialize BERT model if any BERT mode is selected
    punc_model = None
    bert_modes = [m for m in modes if m.startswith("bert")]
    if bert_modes:
        print("Loading FunASR CT-Transformer punctuation model...")
        from benchmark_punctuation import PunctuationModel
        punc_model = PunctuationModel()
        print("Punctuation model loaded.\n")

    for mode in modes:
        print(f"\n{'#'*60}")
        print(f"# Mode: {mode}")
        print(f"{'#'*60}")

        if mode == "llm-only":
            # Original single-layer LLM benchmark
            for prompt_key in prompts:
                all_results = {"models": {}}
                for model in models:
                    print(f"\n[llm-only] {prompt_key} × {model}")
                    print("=" * 60)
                    try:
                        model_results = run_benchmark(
                            str(testcases_path), model=model,
                            base_url=args.url, prompt_key=prompt_key,
                        )
                        all_results["models"][model] = model_results
                        print(f"  加權總分: {model_results['avg_weighted']:.1f}")
                    except Exception as e:
                        print(f"Error: {e}")
                        continue

                if all_results["models"]:
                    _save_results(
                        all_results, output_dir,
                        f"llm-only_{prompt_key}", timestamp, prompt_key,
                    )

        elif mode in ("bert-only", "bert+regex"):
            # No LLM needed, run once
            print(f"\n[{mode}] Running...")
            print("=" * 60)
            result = run_two_layer_benchmark(
                str(testcases_path), mode=mode, punc_model=punc_model,
            )
            all_results = {"models": {mode: result}}
            print(f"  加權總分: {result['avg_weighted']:.1f}")
            _save_results(all_results, output_dir, mode, timestamp, mode)

        elif mode == "bert+llm":
            all_results = {"models": {}}
            for model in models:
                print(f"\n[bert+llm] {model}")
                print("=" * 60)
                try:
                    result = run_two_layer_benchmark(
                        str(testcases_path), mode="bert+llm",
                        punc_model=punc_model, model=model,
                        base_url=args.url,
                    )
                    all_results["models"][model] = result
                    print(f"  加權總分: {result['avg_weighted']:.1f}")
                except Exception as e:
                    print(f"Error: {e}")
                    continue

            if all_results["models"]:
                _save_results(
                    all_results, output_dir, "bert+llm", timestamp, "v5-term-only",
                )


def _save_results(
    all_results: dict, output_dir: Path,
    label: str, timestamp: str, prompt_key: str,
):
    """Save JSON results and Markdown report."""
    json_path = output_dir / f"results_{label}_{timestamp}.json"
    with open(json_path, "w") as f:
        serializable = json.loads(json.dumps(all_results, default=str))
        json.dump(serializable, f, ensure_ascii=False, indent=2)
    print(f"\n原始結果: {json_path}")

    report = generate_report(all_results, prompt_key=prompt_key)
    report_path = output_dir / f"report_{label}_{timestamp}.md"
    with open(report_path, "w") as f:
        f.write(report)
    print(f"比較報告: {report_path}")
```

**Step 2: Run all existing tests to verify no regressions**

Run: `apps/mac-client/python/.venv/bin/python -m pytest scripts/tests/ -v`
Expected: All passed

**Step 3: Commit**

```bash
git add scripts/benchmark_llm.py
git commit -m "feat: add --mode CLI parameter for two-layer pipeline benchmark"
```

---

### Task 5: E2E verification — run full benchmark

**Step 1: Verify FunASR model downloads and works**

Run a quick smoke test:
```bash
apps/mac-client/python/.venv/bin/python -c "
from benchmark_punctuation import PunctuationModel
pm = PunctuationModel()
result = pm.add_punctuation('今天天氣很好我們去散步')
print(f'Result: {result}')
assert '，' in result or '。' in result, 'No punctuation added'
print('OK')
"
```

Expected: Model downloads (~72MB first time), outputs punctuated Traditional Chinese text.

**Step 2: Run bert-only and bert+regex modes**

```bash
apps/mac-client/python/.venv/bin/python scripts/benchmark_llm.py --mode bert-only bert+regex
```

Expected: Two results files in `scripts/benchmark_results/`. The `bert+regex` mode should show high terminology scores (100% for exact matches) and high punctuation F1.

**Step 3: Run bert+llm mode with one model**

```bash
apps/mac-client/python/.venv/bin/python scripts/benchmark_llm.py --mode bert+llm --models qwen/qwen3-4b
```

Expected: Results with BERT punctuation + LLM terminology correction using v5-term-only prompt.

**Step 4: Compare all modes**

Run all modes together:
```bash
apps/mac-client/python/.venv/bin/python scripts/benchmark_llm.py --mode all --models qwen/qwen3-4b
```

Expected: Four result files, one per mode. Compare weighted scores across modes.

**Step 5: Commit any fixes from E2E testing**

```bash
git add -A
git commit -m "fix: adjustments from E2E benchmark verification"
```
