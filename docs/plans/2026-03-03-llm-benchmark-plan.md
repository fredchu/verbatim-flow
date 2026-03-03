# LLM ASR Post-Processing Benchmark 實作計畫

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 建立自動化 benchmark 腳本，透過 LM Studio OpenAI-compatible API 評測不同 MLX 模型在 ASR 後處理（術語校正、加標點、文字保留度）上的表現。

**Architecture:** 獨立 Python 腳本（無框架依賴），讀取 JSON 測試集，逐條送 LM Studio API，收集回應後用四個指標自動評分，輸出 JSON 原始結果 + Markdown 比較報告。互動式切換模型。

**Tech Stack:** Python 3.10+、requests（HTTP）、標準庫（json, time, re, difflib, pathlib, datetime）

---

### Task 1: 建立測試資料集

**Files:**
- Create: `scripts/benchmark_testcases.json`

**Step 1: 建立測試資料集檔案**

根據使用者實測的 ASR 誤識別案例，建立 15 則 short + 5 則 long 測試案例。每則包含 `id`、`input`（ASR 原始輸出）、`expected`（人工標註正確結果）、`terminology_corrections`（應替換的術語列表）、`type`（short/long）。

```json
[
  {
    "id": "t01",
    "input": "目前使用歐拉瑪的Quant 38B進行校正跟幫Brice ASR加標點符號我想要換成用LIM Studio搭配Quant 38B M2X的模型評估可行性",
    "expected": "目前使用 Ollama 的 Qwen3 8B 進行校正，跟幫 Breeze ASR 加標點符號。我想要換成用 LM Studio 搭配 Qwen3 8B MLX 的模型，評估可行性。",
    "terminology_corrections": ["Ollama", "Qwen3 8B", "Breeze ASR", "LM Studio", "MLX"],
    "type": "short"
  },
  {
    "id": "t02",
    "input": "目前使用歐拉瑪的Quant 38B進行校正搭配Bruce ASR加標點符號欲轉用LIM Studio搭配Quant 38B Emerald X組合可行性欲以Super powers的技能組合整合至Git Hub先不動手",
    "expected": "目前使用 Ollama 的 Qwen3 8B 進行校正，搭配 Breeze ASR 加標點符號。欲轉用 LM Studio 搭配 Qwen3 8B MLX 組合，可行性欲以 Superpowers 的技能組合整合至 GitHub，先不動手。",
    "terminology_corrections": ["Ollama", "Qwen3 8B", "Breeze ASR", "LM Studio", "MLX", "Superpowers", "GitHub"],
    "type": "short"
  },
  {
    "id": "t03",
    "input": "我要用Cloud Code來寫一個work flow自動化Comet和Release的流程",
    "expected": "我要用 Claude Code 來寫一個 workflow，自動化 Commit 和 Release 的流程。",
    "terminology_corrections": ["Claude Code", "workflow", "Commit"],
    "type": "short"
  },
  {
    "id": "t04",
    "input": "這個偷坑的集聚設定有問題需要調整一下",
    "expected": "這個 token 的級距設定有問題，需要調整一下。",
    "terminology_corrections": ["token", "級距"],
    "type": "short"
  },
  {
    "id": "t05",
    "input": "我在Git Hub上面開了一個新的Codex專案用的是Open AI的GPT模型",
    "expected": "我在 GitHub 上面開了一個新的 Codex 專案，用的是 OpenAI 的 GPT 模型。",
    "terminology_corrections": ["GitHub", "Codex", "OpenAI", "GPT"],
    "type": "short"
  },
  {
    "id": "t06",
    "input": "把B肉的片段剪出來然後用SRT格式匯出字幕檔",
    "expected": "把 BROLL 的片段剪出來，然後用 SRT 格式匯出字幕檔。",
    "terminology_corrections": ["BROLL", "SRT"],
    "type": "short"
  },
  {
    "id": "t07",
    "input": "用Gemini CLI跑一下測試然後跟Chat GPT的結果比較看看",
    "expected": "用 Gemini CLI 跑一下測試，然後跟 ChatGPT 的結果比較看看。",
    "terminology_corrections": ["Gemini CLI", "ChatGPT"],
    "type": "short"
  },
  {
    "id": "t08",
    "input": "Brise ASR的Forced Aligner功能可以自動對齊字幕時間軸",
    "expected": "Breeze ASR 的 ForcedAligner 功能可以自動對齊字幕時間軸。",
    "terminology_corrections": ["Breeze ASR", "ForcedAligner"],
    "type": "short"
  },
  {
    "id": "t09",
    "input": "用Open CC把簡體轉成繁體然後再跑一次Quint 3 ASR看看結果有沒有改善",
    "expected": "用 OpenCC 把簡體轉成繁體，然後再跑一次 Qwen3 ASR 看看結果有沒有改善。",
    "terminology_corrections": ["OpenCC", "Qwen3 ASR"],
    "type": "short"
  },
  {
    "id": "t10",
    "input": "Anthropic剛發布了新的模型我們來測試一下跟Google的Gemini比較",
    "expected": "Anthropic 剛發布了新的模型，我們來測試一下，跟 Google 的 Gemini 比較。",
    "terminology_corrections": ["Anthropic", "Google", "Gemini"],
    "type": "short"
  },
  {
    "id": "t11",
    "input": "這個Super power的walk flow需要先Comet到main branch然後再做Release",
    "expected": "這個 Superpowers 的 workflow 需要先 Commit 到 main branch，然後再做 Release。",
    "terminology_corrections": ["Superpowers", "workflow", "Commit", "Release"],
    "type": "short"
  },
  {
    "id": "t12",
    "input": "逼肉的部分我已經剪好了接下來要處理主要的訪談內容",
    "expected": "BROLL 的部分我已經剪好了，接下來要處理主要的訪談內容。",
    "terminology_corrections": ["BROLL"],
    "type": "short"
  },
  {
    "id": "t13",
    "input": "今天要來錄一集關於AI工具的影片主要會介紹Cloud Code跟Gemini CLI這兩個工具",
    "expected": "今天要來錄一集關於 AI 工具的影片，主要會介紹 Claude Code 跟 Gemini CLI 這兩個工具。",
    "terminology_corrections": ["Claude Code", "Gemini CLI"],
    "type": "short"
  },
  {
    "id": "t14",
    "input": "每個偷坑的集聚不一樣所以價格計算方式也不同",
    "expected": "每個 token 的級距不一樣，所以價格計算方式也不同。",
    "terminology_corrections": ["token", "級距"],
    "type": "short"
  },
  {
    "id": "t15",
    "input": "先把Git上面的分支整理一下然後再開一個新的branch來做這個功能",
    "expected": "先把 Git 上面的分支整理一下，然後再開一個新的 branch 來做這個功能。",
    "terminology_corrections": ["Git"],
    "type": "short"
  },
  {
    "id": "t16",
    "input": "今天我們要來介紹一下怎麼用歐拉瑪在本地端跑大型語言模型首先你需要安裝歐拉瑪這個軟體然後下載你想要用的模型比如說Quint 3或者是Gemini接著你就可以透過API來呼叫這些模型了整個過程其實非常簡單大概五分鐘就可以搞定",
    "expected": "今天我們要來介紹一下怎麼用 Ollama 在本地端跑大型語言模型。首先你需要安裝 Ollama 這個軟體，然後下載你想要用的模型，比如說 Qwen3 或者是 Gemini。接著你就可以透過 API 來呼叫這些模型了。整個過程其實非常簡單，大概五分鐘就可以搞定。",
    "terminology_corrections": ["Ollama", "Qwen3", "Gemini"],
    "type": "long"
  },
  {
    "id": "t17",
    "input": "這個專案目前用的是Brise ASR做語音辨識然後透過Cloud Code來做自動化的work flow包含了自動Comet到Git Hub上面還有自動產生Release notes另外我們也有用Open CC來做簡繁轉換確保所有的字幕都是繁體中文的",
    "expected": "這個專案目前用的是 Breeze ASR 做語音辨識，然後透過 Claude Code 來做自動化的 workflow。包含了自動 Commit 到 GitHub 上面，還有自動產生 Release notes。另外我們也有用 OpenCC 來做簡繁轉換，確保所有的字幕都是繁體中文的。",
    "terminology_corrections": ["Breeze ASR", "Claude Code", "workflow", "Commit", "GitHub", "Release", "OpenCC"],
    "type": "long"
  },
  {
    "id": "t18",
    "input": "接下來我要示範怎麼用Super powers的技能組合來建立一個完整的開發流程從brainstorming開始然後寫設計文件接著用TDD的方式來寫程式碼最後再做code review確保品質這整個walk flow都可以透過Cloud Code來自動化",
    "expected": "接下來我要示範怎麼用 Superpowers 的技能組合來建立一個完整的開發流程。從 brainstorming 開始，然後寫設計文件，接著用 TDD 的方式來寫程式碼，最後再做 code review 確保品質。這整個 workflow 都可以透過 Claude Code 來自動化。",
    "terminology_corrections": ["Superpowers", "workflow", "Claude Code"],
    "type": "long"
  },
  {
    "id": "t19",
    "input": "我們來看一下影片製作的流程首先是拍攝逼肉跟主要內容然後用Forced Aligner來自動對齊字幕接著匯出SRT格式的字幕檔最後用Open CC把簡體部分轉成繁體整個過程大概需要十分鐘左右",
    "expected": "我們來看一下影片製作的流程。首先是拍攝 BROLL 跟主要內容，然後用 ForcedAligner 來自動對齊字幕，接著匯出 SRT 格式的字幕檔。最後用 OpenCC 把簡體部分轉成繁體。整個過程大概需要十分鐘左右。",
    "terminology_corrections": ["BROLL", "ForcedAligner", "SRT", "OpenCC"],
    "type": "long"
  },
  {
    "id": "t20",
    "input": "現在來比較一下不同的AI工具Open AI的Chat GPT跟Anthropic的Cloud Code還有Google的Gemini CLI各有各的優缺點Chat GPT適合一般對話Cloud Code適合寫程式Gemini CLI適合跟Google的服務整合大家可以根據自己的需求來選擇",
    "expected": "現在來比較一下不同的 AI 工具。OpenAI 的 ChatGPT 跟 Anthropic 的 Claude Code，還有 Google 的 Gemini CLI，各有各的優缺點。ChatGPT 適合一般對話，Claude Code 適合寫程式，Gemini CLI 適合跟 Google 的服務整合。大家可以根據自己的需求來選擇。",
    "terminology_corrections": ["OpenAI", "ChatGPT", "Anthropic", "Claude Code", "Google", "Gemini CLI"],
    "type": "long"
  }
]
```

**Step 2: 驗證 JSON 格式正確**

Run: `python3 -c "import json; d=json.load(open('scripts/benchmark_testcases.json')); print(f'{len(d)} test cases loaded: {sum(1 for t in d if t[\"type\"]==\"short\")} short, {sum(1 for t in d if t[\"type\"]==\"long\")} long')"`

Expected: `20 test cases loaded: 15 short, 5 long`

**Step 3: Commit**

```bash
git add scripts/benchmark_testcases.json
git commit -m "test: add benchmark test cases for LLM ASR post-processing"
```

---

### Task 2: 評分函式（scoring module）

**Files:**
- Create: `scripts/benchmark_llm.py`（先寫評分部分）
- Create: `scripts/tests/test_benchmark_scoring.py`

**Step 1: 寫評分函式的測試**

```python
# scripts/tests/test_benchmark_scoring.py
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from benchmark_llm import score_terminology, score_preservation, score_punctuation

class TestTerminologyScoring:
    def test_all_correct(self):
        output = "使用 Ollama 的 Qwen3 8B 搭配 Breeze ASR"
        corrections = ["Ollama", "Qwen3 8B", "Breeze ASR"]
        assert score_terminology(output, corrections) == 100.0

    def test_partial(self):
        output = "使用 Ollama 的 Quant 38B 搭配 Brice ASR"
        corrections = ["Ollama", "Qwen3 8B", "Breeze ASR"]
        result = score_terminology(output, corrections)
        assert abs(result - 33.33) < 1  # 1 out of 3

    def test_none_correct(self):
        output = "使用歐拉瑪的 Quant 38B 搭配 Brice ASR"
        corrections = ["Ollama", "Qwen3 8B", "Breeze ASR"]
        assert score_terminology(output, corrections) == 0.0

    def test_empty_corrections(self):
        output = "今天天氣很好"
        corrections = []
        assert score_terminology(output, corrections) == 100.0

class TestPreservationScoring:
    def test_no_extra_edits(self):
        # input after removing punctuation and known terms = output after same
        input_text = "今天天氣很好我們去散步"
        output_text = "今天天氣很好，我們去散步。"
        terminology = []
        score = score_preservation(input_text, output_text, terminology)
        assert score == 100.0

    def test_heavy_rewrite(self):
        input_text = "今天天氣很好我們去散步"
        output_text = "今日天候良好，吾等前往散步。"
        terminology = []
        score = score_preservation(input_text, output_text, terminology)
        assert score < 60  # significant rewrite

    def test_terminology_replacement_not_penalized(self):
        input_text = "使用歐拉瑪來跑模型"
        output_text = "使用 Ollama 來跑模型。"
        terminology = ["歐拉瑪→Ollama"]
        score = score_preservation(input_text, output_text, terminology)
        assert score >= 90  # terminology swap should not be penalized

class TestPunctuationScoring:
    def test_perfect_punctuation(self):
        expected = "今天天氣很好，我們去散步。"
        output = "今天天氣很好，我們去散步。"
        p, r, f1 = score_punctuation(expected, output)
        assert f1 == 100.0

    def test_missing_punctuation(self):
        expected = "今天天氣很好，我們去散步。"
        output = "今天天氣很好我們去散步。"
        p, r, f1 = score_punctuation(expected, output)
        assert r < 100  # missed a comma
        assert f1 < 100

    def test_no_punctuation_in_output(self):
        expected = "今天天氣很好，我們去散步。"
        output = "今天天氣很好我們去散步"
        p, r, f1 = score_punctuation(expected, output)
        assert f1 < 50
```

**Step 2: 執行測試確認失敗**

Run: `cd /Users/fredchu/dev/verbatim-flow && python3 -m pytest scripts/tests/test_benchmark_scoring.py -v`

Expected: FAIL（`benchmark_llm` 模組不存在）

**Step 3: 實作評分函式**

在 `scripts/benchmark_llm.py` 中實作三個評分函式：

```python
#!/usr/bin/env python3
"""LLM ASR Post-Processing Benchmark Tool."""

import re
from difflib import SequenceMatcher

# --- 常數 ---

PUNCTUATION_CHARS = set("，。！？；：、「」『』《》")

SYSTEM_PROMPT = """你是標點與術語校正器。
規則：
- 只加標點符號（，。！？；：「」），不修改任何文字內容。
- 唯一例外：套用以下術語替換表，將語音誤識別的詞彙修正為正確寫法。
- 不刪字、不加字、不改寫、不潤飾、不合併語句。
- 使用全形標點符號。
- 術語替換：歐拉瑪 → Ollama｜Comet → Commit｜walk flow → workflow｜work flow → workflow｜偷坑 → token｜B肉 → BROLL｜逼肉 → BROLL｜Cloud Code → Claude Code｜Super power → Superpowers｜Super powers → Superpowers｜Brise ASR → Breeze ASR｜Bruce ASR → Breeze ASR｜Brice ASR → Breeze ASR｜Quint 3 → Qwen3｜Quant 3 → Qwen3｜Quant 38B → Qwen3 8B｜集聚 → 級距｜LIM Studio → LM Studio｜Emerald X → MLX｜M2X → MLX
- 僅輸出結果，不要解釋。 /no_think"""


def _strip_punctuation(text: str) -> str:
    """Remove all CJK punctuation characters from text."""
    return "".join(ch for ch in text if ch not in PUNCTUATION_CHARS)


def _strip_spaces(text: str) -> str:
    """Remove all whitespace from text."""
    return re.sub(r"\s+", "", text)


def _apply_terminology_removals(text: str, terminology: list[str]) -> str:
    """Remove known terminology pairs from text for fair comparison.

    terminology items can be either:
    - "correct_term" (just check presence)
    - "wrong→correct" (for preservation scoring, remove both forms)
    """
    result = text
    for item in terminology:
        if "→" in item:
            wrong, correct = item.split("→", 1)
            result = result.replace(wrong.strip(), "")
            result = result.replace(correct.strip(), "")
        else:
            result = result.replace(item.strip(), "")
    return result


# --- 評分函式 ---


def score_terminology(output: str, corrections: list[str]) -> float:
    """Calculate terminology recall: how many expected terms appear in output.

    Args:
        output: Model output text.
        corrections: List of correct terms that should appear in output.

    Returns:
        Score 0-100.
    """
    if not corrections:
        return 100.0
    found = sum(1 for term in corrections if term in output)
    return round(found / len(corrections) * 100, 2)


def score_preservation(
    input_text: str, output_text: str, terminology: list[str]
) -> float:
    """Calculate text preservation: how much extra editing the model did.

    Strips punctuation and known terminology replacements from both texts,
    then computes character-level edit distance.

    Args:
        input_text: Original ASR input.
        output_text: Model output.
        terminology: List of "wrong→correct" pairs or plain terms.

    Returns:
        Score 0-100. 100 = no extra edits beyond punctuation and terminology.
    """
    clean_input = _strip_spaces(_strip_punctuation(
        _apply_terminology_removals(input_text, terminology)
    ))
    clean_output = _strip_spaces(_strip_punctuation(
        _apply_terminology_removals(output_text, terminology)
    ))

    if not clean_input and not clean_output:
        return 100.0

    matcher = SequenceMatcher(None, clean_input, clean_output)
    # Number of characters that differ
    edits = sum(
        max(j2 - j1, i2 - i1)
        for tag, i1, i2, j1, j2 in matcher.get_opcodes()
        if tag != "equal"
    )
    return max(0.0, round(100 - edits * 5, 2))


def score_punctuation(expected: str, output: str) -> tuple[float, float, float]:
    """Calculate punctuation precision, recall, F1.

    Compares punctuation positions (character index after stripping punctuation)
    between expected and output texts.

    Args:
        expected: Gold standard text with correct punctuation.
        output: Model output text.

    Returns:
        Tuple of (precision, recall, f1), each 0-100.
    """
    def _get_punctuation_positions(text: str) -> set[tuple[int, str]]:
        """Get set of (position_in_stripped_text, punct_char)."""
        positions = set()
        stripped_idx = 0
        for ch in text:
            if ch in PUNCTUATION_CHARS:
                positions.add((stripped_idx, ch))
            elif not ch.isspace():
                stripped_idx += 1
        return positions

    expected_pos = _get_punctuation_positions(expected)
    output_pos = _get_punctuation_positions(output)

    if not expected_pos and not output_pos:
        return 100.0, 100.0, 100.0
    if not expected_pos:
        return 0.0, 100.0, 0.0
    if not output_pos:
        return 100.0, 0.0, 0.0

    # Lenient mode: match position only, ignore punctuation type
    expected_indices = {pos for pos, _ in expected_pos}
    output_indices = {pos for pos, _ in output_pos}

    true_positives = len(expected_indices & output_indices)

    precision = true_positives / len(output_indices) * 100 if output_indices else 0
    recall = true_positives / len(expected_indices) * 100 if expected_indices else 0
    f1 = (
        2 * precision * recall / (precision + recall)
        if (precision + recall) > 0
        else 0
    )
    return round(precision, 2), round(recall, 2), round(f1, 2)
```

**Step 4: 執行測試確認通過**

Run: `cd /Users/fredchu/dev/verbatim-flow && python3 -m pytest scripts/tests/test_benchmark_scoring.py -v`

Expected: 全部 PASS（9 tests）

**Step 5: Commit**

```bash
git add scripts/benchmark_llm.py scripts/tests/test_benchmark_scoring.py
git commit -m "feat: add scoring functions for LLM benchmark (terminology, preservation, punctuation)"
```

---

### Task 3: API 呼叫與結果收集

**Files:**
- Modify: `scripts/benchmark_llm.py`（加入 API 呼叫邏輯）

**Step 1: 寫 API 呼叫的測試**

新增到 `scripts/tests/test_benchmark_scoring.py`：

```python
from benchmark_llm import call_llm

class TestCallLLM:
    def test_request_format(self):
        """Verify the request payload structure (mock test)."""
        import unittest.mock as mock

        fake_response = mock.MagicMock()
        fake_response.json.return_value = {
            "choices": [{"message": {"content": "測試結果。"}}],
            "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15},
        }
        fake_response.raise_for_status = mock.MagicMock()

        with mock.patch("benchmark_llm.requests.post", return_value=fake_response) as mock_post:
            result = call_llm("測試輸入", "http://localhost:1234")
            assert result["content"] == "測試結果。"
            assert result["usage"]["total_tokens"] == 15

            # Verify request structure
            call_args = mock_post.call_args
            payload = call_args[1]["json"]
            assert payload["messages"][0]["role"] == "system"
            assert payload["messages"][1]["role"] == "user"
            assert payload["messages"][1]["content"] == "測試輸入"
            assert payload["temperature"] == 0
```

**Step 2: 執行測試確認失敗**

Run: `python3 -m pytest scripts/tests/test_benchmark_scoring.py::TestCallLLM -v`

Expected: FAIL（`call_llm` 不存在）

**Step 3: 實作 `call_llm`**

在 `scripts/benchmark_llm.py` 中加入：

```python
import time
import requests

LM_STUDIO_DEFAULT_URL = "http://localhost:1234"


def call_llm(
    input_text: str, base_url: str = LM_STUDIO_DEFAULT_URL
) -> dict:
    """Send input to LM Studio OpenAI-compatible API.

    Args:
        input_text: The ASR text to process.
        base_url: LM Studio server URL.

    Returns:
        Dict with keys: content, usage, elapsed_s, tokens_per_sec
    """
    payload = {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": input_text},
        ],
        "temperature": 0,
        "max_tokens": 2048,
    }

    start = time.time()
    resp = requests.post(
        f"{base_url}/v1/chat/completions",
        json=payload,
        timeout=120,
    )
    elapsed = time.time() - start
    resp.raise_for_status()

    data = resp.json()
    usage = data.get("usage", {})
    completion_tokens = usage.get("completion_tokens", 0)
    tokens_per_sec = completion_tokens / elapsed if elapsed > 0 else 0

    return {
        "content": data["choices"][0]["message"]["content"].strip(),
        "usage": usage,
        "elapsed_s": round(elapsed, 3),
        "tokens_per_sec": round(tokens_per_sec, 1),
    }
```

**Step 4: 執行測試確認通過**

Run: `python3 -m pytest scripts/tests/test_benchmark_scoring.py::TestCallLLM -v`

Expected: PASS

**Step 5: Commit**

```bash
git add scripts/benchmark_llm.py scripts/tests/test_benchmark_scoring.py
git commit -m "feat: add LM Studio API call function for benchmark"
```

---

### Task 4: 報告產生器

**Files:**
- Modify: `scripts/benchmark_llm.py`（加入報告產生邏輯）

**Step 1: 寫報告產生的測試**

新增到 `scripts/tests/test_benchmark_scoring.py`：

```python
from benchmark_llm import generate_report

class TestReportGeneration:
    def test_generates_markdown(self):
        results = {
            "models": {
                "qwen3-8b-8bit": {
                    "cases": [
                        {
                            "id": "t01",
                            "input": "歐拉瑪",
                            "expected": "Ollama。",
                            "output": "Ollama。",
                            "terminology_score": 100.0,
                            "preservation_score": 100.0,
                            "punctuation_f1": 100.0,
                            "weighted_score": 100.0,
                            "tokens_per_sec": 30.0,
                            "terminology_detail": [("Ollama", True)],
                        }
                    ],
                    "avg_terminology": 100.0,
                    "avg_preservation": 100.0,
                    "avg_punctuation_f1": 100.0,
                    "avg_weighted": 100.0,
                    "avg_tokens_per_sec": 30.0,
                }
            }
        }
        report = generate_report(results)
        assert "# LLM ASR Post-Processing Benchmark" in report
        assert "qwen3-8b-8bit" in report
        assert "100.0" in report
```

**Step 2: 執行測試確認失敗**

Run: `python3 -m pytest scripts/tests/test_benchmark_scoring.py::TestReportGeneration -v`

Expected: FAIL

**Step 3: 實作 `generate_report`**

在 `scripts/benchmark_llm.py` 中加入：

```python
from datetime import datetime


def generate_report(results: dict) -> str:
    """Generate Markdown comparison report.

    Args:
        results: Dict with "models" key containing per-model results.

    Returns:
        Markdown string.
    """
    lines = [
        "# LLM ASR Post-Processing Benchmark",
        f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        "Prompt: v1",
        "",
        "## 綜合排名",
        "| # | 模型 | 術語(40%) | 保留度(30%) | 標點(30%) | 加權總分 | tok/s |",
        "|---|---|---|---|---|---|---|",
    ]

    # Sort models by weighted score descending
    ranked = sorted(
        results["models"].items(),
        key=lambda x: x[1]["avg_weighted"],
        reverse=True,
    )

    for rank, (model_name, model_data) in enumerate(ranked, 1):
        lines.append(
            f"| {rank} | {model_name} "
            f"| {model_data['avg_terminology']:.1f} "
            f"| {model_data['avg_preservation']:.1f} "
            f"| {model_data['avg_punctuation_f1']:.1f} "
            f"| {model_data['avg_weighted']:.1f} "
            f"| {model_data['avg_tokens_per_sec']:.0f} |"
        )

    lines.append("")
    lines.append("## 各案例明細")

    # Detail section: show each test case across all models
    if ranked:
        first_model_cases = ranked[0][1]["cases"]
        for case in first_model_cases:
            case_id = case["id"]
            lines.append(f"### {case_id}")
            lines.append(f"- 輸入: {case['input']}")
            lines.append(f"- 期望: {case['expected']}")

            for model_name, model_data in ranked:
                matching = [c for c in model_data["cases"] if c["id"] == case_id]
                if matching:
                    c = matching[0]
                    term_marks = " ".join(
                        f"{'✓' if ok else '✗'}{term}"
                        for term, ok in c["terminology_detail"]
                    )
                    lines.append(
                        f"- {model_name}: {c['output']} "
                        f"[術語:{c['terminology_score']:.0f} "
                        f"保留:{c['preservation_score']:.0f} "
                        f"標點:{c['punctuation_f1']:.0f}] "
                        f"{term_marks}"
                    )
            lines.append("")

    return "\n".join(lines)
```

**Step 4: 執行測試確認通過**

Run: `python3 -m pytest scripts/tests/test_benchmark_scoring.py::TestReportGeneration -v`

Expected: PASS

**Step 5: Commit**

```bash
git add scripts/benchmark_llm.py scripts/tests/test_benchmark_scoring.py
git commit -m "feat: add Markdown report generator for benchmark"
```

---

### Task 5: 主程式（互動式 CLI）

**Files:**
- Modify: `scripts/benchmark_llm.py`（加入 `main` + CLI 邏輯）

**Step 1: 實作主程式**

在 `scripts/benchmark_llm.py` 底部加入：

```python
import json
from pathlib import Path


def run_benchmark(
    testcases_path: str,
    base_url: str = LM_STUDIO_DEFAULT_URL,
    output_dir: str = "scripts/benchmark_results",
) -> dict:
    """Run benchmark for one model.

    Args:
        testcases_path: Path to benchmark_testcases.json.
        base_url: LM Studio API URL.
        output_dir: Directory for results.

    Returns:
        Dict with per-case results and averages.
    """
    with open(testcases_path) as f:
        testcases = json.load(f)

    cases = []
    for tc in testcases:
        print(f"  [{tc['id']}] {tc['input'][:40]}...")
        result = call_llm(tc["input"], base_url)

        term_score = score_terminology(result["content"], tc["terminology_corrections"])
        pres_score = score_preservation(tc["input"], result["content"], tc.get("terminology_pairs", []))
        prec, rec, f1 = score_punctuation(tc["expected"], result["content"])
        weighted = term_score * 0.4 + pres_score * 0.3 + f1 * 0.3

        term_detail = [
            (term, term in result["content"])
            for term in tc["terminology_corrections"]
        ]

        cases.append({
            "id": tc["id"],
            "type": tc["type"],
            "input": tc["input"],
            "expected": tc["expected"],
            "output": result["content"],
            "terminology_score": term_score,
            "preservation_score": pres_score,
            "punctuation_precision": prec,
            "punctuation_recall": rec,
            "punctuation_f1": f1,
            "weighted_score": round(weighted, 2),
            "tokens_per_sec": result["tokens_per_sec"],
            "elapsed_s": result["elapsed_s"],
            "terminology_detail": term_detail,
        })

        status = "✓" if term_score == 100 else f"術語:{term_score:.0f}"
        print(f"         → {status} | 保留:{pres_score:.0f} | 標點F1:{f1:.0f} | {result['tokens_per_sec']:.0f} tok/s")

    avg = lambda key: round(sum(c[key] for c in cases) / len(cases), 2)

    return {
        "cases": cases,
        "avg_terminology": avg("terminology_score"),
        "avg_preservation": avg("preservation_score"),
        "avg_punctuation_f1": avg("punctuation_f1"),
        "avg_weighted": avg("weighted_score"),
        "avg_tokens_per_sec": avg("tokens_per_sec"),
    }


def main():
    """Interactive CLI for running benchmarks across multiple models."""
    testcases_path = Path(__file__).parent / "benchmark_testcases.json"
    output_dir = Path(__file__).parent / "benchmark_results"
    output_dir.mkdir(exist_ok=True)

    if not testcases_path.exists():
        print(f"Error: {testcases_path} not found")
        return

    all_results = {"models": {}}
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    print("=" * 60)
    print("LLM ASR Post-Processing Benchmark")
    print("=" * 60)
    print(f"Test cases: {testcases_path}")
    print(f"LM Studio API: {LM_STUDIO_DEFAULT_URL}")
    print()

    while True:
        model_name = input("輸入模型名稱（如 qwen3-8b-8bit），或 'q' 結束: ").strip()
        if model_name.lower() == "q":
            break
        if not model_name:
            continue

        print(f"\n--- 測試模型: {model_name} ---")
        try:
            model_results = run_benchmark(str(testcases_path))
            all_results["models"][model_name] = model_results

            print(f"\n=== {model_name} 結果 ===")
            print(f"  術語校正率: {model_results['avg_terminology']:.1f}")
            print(f"  文字保留度: {model_results['avg_preservation']:.1f}")
            print(f"  標點 F1:    {model_results['avg_punctuation_f1']:.1f}")
            print(f"  加權總分:   {model_results['avg_weighted']:.1f}")
            print(f"  平均速度:   {model_results['avg_tokens_per_sec']:.0f} tok/s")
        except Exception as e:
            print(f"Error: {e}")
            print("請確認 LM Studio 已啟動並載入模型。")
            continue

        print()

    if all_results["models"]:
        # Save raw JSON
        json_path = output_dir / f"results_{timestamp}.json"
        with open(json_path, "w") as f:
            # Convert terminology_detail tuples to lists for JSON
            serializable = json.loads(json.dumps(all_results, default=str))
            json.dump(serializable, f, ensure_ascii=False, indent=2)
        print(f"\n原始結果: {json_path}")

        # Save Markdown report
        report = generate_report(all_results)
        report_path = output_dir / f"report_{timestamp}.md"
        with open(report_path, "w") as f:
            f.write(report)
        print(f"比較報告: {report_path}")
    else:
        print("沒有測試結果。")


if __name__ == "__main__":
    main()
```

**Step 2: 確認腳本可以啟動（不連 API）**

Run: `cd /Users/fredchu/dev/verbatim-flow && python3 -c "from scripts.benchmark_llm import main; print('Import OK')"`

Expected: `Import OK`

**Step 3: Commit**

```bash
git add scripts/benchmark_llm.py
git commit -m "feat: add interactive CLI for LLM benchmark runner"
```

---

### Task 6: 端到端測試（連接 LM Studio）

**Files:**
- No new files

**Step 1: 確認 LM Studio 運作中**

Run: `curl -s http://localhost:1234/v1/models | python3 -m json.tool | head -20`

Expected: 回傳目前載入的模型資訊（若 LM Studio 未啟動會報 connection refused）

**Step 2: 用單一測試案例測試**

Run: `cd /Users/fredchu/dev/verbatim-flow && python3 -c "
from scripts.benchmark_llm import call_llm, score_terminology
result = call_llm('我要用Cloud Code來寫一個work flow')
print('Output:', result['content'])
print('Speed:', result['tokens_per_sec'], 'tok/s')
print('Terminology:', score_terminology(result['content'], ['Claude Code', 'workflow']))
"`

Expected: 輸出含 "Claude Code" 和 "workflow"，術語分數 100

**Step 3: 確認所有測試通過**

Run: `cd /Users/fredchu/dev/verbatim-flow && python3 -m pytest scripts/tests/test_benchmark_scoring.py -v`

Expected: 全部 PASS

**Step 4: 加 .gitignore 排除結果檔**

在 `.gitignore` 中加入：

```
scripts/benchmark_results/
```

**Step 5: Final commit**

```bash
git add scripts/benchmark_llm.py scripts/tests/ .gitignore
git commit -m "feat: complete LLM ASR benchmark tool with scoring, API, and reporting"
```

---

### 執行指南

測試完成後，實際使用流程：

```bash
cd /Users/fredchu/dev/verbatim-flow
python3 scripts/benchmark_llm.py
```

1. 在 LM Studio 載入第一個模型（如 Qwen3-0.6B-8bit）
2. 在終端輸入模型名稱 `qwen3-0.6b-8bit`
3. 等待 20 則測試跑完
4. 在 LM Studio 切換下一個模型
5. 重複直到所有 8 個模型測試完
6. 輸入 `q` 結束，查看 `scripts/benchmark_results/` 下的報告
