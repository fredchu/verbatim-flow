# Regex 術語替換改進 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把 `apply_terminology_regex()` 從 `str.replace` 改為 `re.sub`，加入 word boundary、IGNORECASE、空格容錯、變體合併。

**Architecture:** 最小改動方案 — `TERMINOLOGY_TABLE` 純文字常量改成 `TERMINOLOGY_RULES` list of tuples `(pattern, replacement, flags)`，函式改用 `re.sub` 逐條套用。25 條規則壓到 20 條。

**Tech Stack:** Python 3, `re` stdlib, pytest

**Design doc:** `docs/plans/2026-03-04-regex-terminology-design.md`

---

### Task 1: 寫新的 regex 行為測試（紅燈）

**Files:**
- Modify: `scripts/tests/test_benchmark_scoring.py:161-182`

**Step 1: 更新既有測試 + 新增 regex 測試**

在 `TestTerminologyRegex` class 中，保留既有 4 個 tests 不動（它們的期望結果在新實作下仍然正確），新增 6 個 tests：

```python
    def test_ignorecase_lower(self):
        result = apply_terminology_regex("用 git hub 管理程式碼")
        assert "GitHub" in result

    def test_ignorecase_upper(self):
        result = apply_terminology_regex("用 GIT HUB 管理")
        assert "GitHub" in result

    def test_word_boundary_protection(self):
        """GitHub should NOT be split by the 'Git Hub' rule."""
        result = apply_terminology_regex("上傳到GitHub吧")
        assert result == "上傳到GitHub吧"

    def test_multi_space_tolerance(self):
        result = apply_terminology_regex("打開 Chat  GPT 問問題")
        assert "ChatGPT" in result

    def test_variant_merge_singular(self):
        result = apply_terminology_regex("這個 Superpower 很強")
        assert "Superpowers" in result

    def test_variant_merge_plural(self):
        result = apply_terminology_regex("這些 Super powers 很強")
        assert "Superpowers" in result

    def test_chinese_in_sentence(self):
        result = apply_terminology_regex("我每天都在偷坑，歐拉瑪很好用")
        assert "token" in result
        assert "Ollama" in result

    def test_combined_chinese_english(self):
        result = apply_terminology_regex("用歐拉瑪的work flow跑Chat GPT")
        assert "Ollama" in result
        assert "workflow" in result
        assert "ChatGPT" in result
```

**Step 2: 跑測試確認新 tests 失敗**

Run: `cd /Users/fredchu/dev/verbatim-flow && python -m pytest scripts/tests/test_benchmark_scoring.py::TestTerminologyRegex -v`

Expected: 新增的 `test_ignorecase_*`、`test_word_boundary_protection`、`test_multi_space_tolerance`、`test_variant_merge_*` 應該 FAIL（現有 `str.replace` 不支援這些行為）。`test_chinese_*` 和 `test_combined_*` 可能 PASS（中文 str.replace 本來就能匹配）。

**Step 3: Commit 紅燈測試**

```bash
git add scripts/tests/test_benchmark_scoring.py
git commit -m "test: add regex terminology tests (red)"
```

---

### Task 2: 實作 TERMINOLOGY_RULES + re.sub

**Files:**
- Modify: `scripts/benchmark_llm.py:16-58`

**Step 1: 把 TERMINOLOGY_TABLE 替換成 TERMINOLOGY_RULES**

刪除 `TERMINOLOGY_TABLE` 字串（lines 16-40），替換為：

```python
TERMINOLOGY_RULES = [
    # (pattern, replacement, flags)

    # --- 英文術語：\b + IGNORECASE ---
    (r'\bGit\s+Hub\b', 'GitHub', re.IGNORECASE),
    (r'\bOpen\s+AI\b', 'OpenAI', re.IGNORECASE),
    (r'\bChat\s+GPT\b', 'ChatGPT', re.IGNORECASE),
    (r'\bOpen\s+CC\b', 'OpenCC', re.IGNORECASE),
    (r'\bCloud\s+Code\b', 'Claude Code', re.IGNORECASE),
    (r'\bSuper\s*powers?\b', 'Superpowers', re.IGNORECASE),
    (r'\bw(?:alk|ork)\s+flow\b', 'workflow', re.IGNORECASE),
    (r'\bLIM\s+Studio\b', 'LM Studio', re.IGNORECASE),
    (r'\bEmerald\s+X\b', 'MLX', re.IGNORECASE),
    (r'\bM2X\b', 'MLX', 0),
    (r'\bComet\b', 'Commit', 0),
    (r'\bForced\s+Aligner\b', 'ForcedAligner', re.IGNORECASE),

    # ASR 音譯模糊匹配
    (r'\bBri[sc]e\s+ASR\b', 'Breeze ASR', re.IGNORECASE),
    (r'\bBruce\s+ASR\b', 'Breeze ASR', re.IGNORECASE),
    (r'\bQu[ai]nt\s*3\b', 'Qwen3', re.IGNORECASE),
    (r'\bQuant\s*3\s*8\s*B\b', 'Qwen3 8B', re.IGNORECASE),

    # --- 中文音譯：無 \b ---
    (r'歐拉瑪', 'Ollama', 0),
    (r'偷坑', 'token', 0),
    (r'[B逼]肉', 'BROLL', 0),
    (r'集聚', '級距', 0),
]
```

**Step 2: 替換 apply_terminology_regex 函式**

刪除現有函式（lines 43-58），替換為：

```python
def apply_terminology_regex(text: str) -> str:
    """Apply terminology corrections using regex patterns."""
    sorted_rules = sorted(TERMINOLOGY_RULES, key=lambda r: len(r[0]), reverse=True)
    for pattern, replacement, flags in sorted_rules:
        text = re.sub(pattern, replacement, text, flags=flags)
    return text
```

**Step 3: 跑全部測試確認綠燈**

Run: `cd /Users/fredchu/dev/verbatim-flow && python -m pytest scripts/tests/test_benchmark_scoring.py::TestTerminologyRegex -v`

Expected: 全部 PASS（既有 4 tests + 新增 8 tests）

**Step 4: Commit**

```bash
git add scripts/benchmark_llm.py
git commit -m "feat: replace str.replace with re.sub for terminology rules"
```

---

### Task 3: Benchmark 回歸驗證

**Files:** 無變更，只跑驗證

**Step 1: 跑完整 test suite**

Run: `cd /Users/fredchu/dev/verbatim-flow && python -m pytest scripts/tests/ -v`

Expected: 全部 PASS

**Step 2: 跑 benchmark**

Run: `cd /Users/fredchu/dev/verbatim-flow && python scripts/benchmark_llm.py --mode bert+regex`

Expected: 加權分數 ≥ 87.2（不退步）

**Step 3: 人工檢查 benchmark 輸出**

檢查 20 個 test cases 的術語替換結果是否合理。特別注意：
- 原本正確的術語（如 `GitHub`）沒有被規則誤改
- 合併的變體（`Super power` / `Super powers`）都正確替換
- 中文音譯替換仍正常

**Step 4: 如果分數退步，檢查哪些 case 被 word boundary 影響**

可能的問題：`\bComet\b` 的 `\b` 在中文字旁邊的行為。如果 `自動Comet` 中的 `Comet` 前面是中文字，`\b` 仍然能匹配（中文字和英文字母之間是 word boundary）。

---

### Task 4: 更新 test 中的 import（如有需要）

**Files:**
- Modify: `scripts/tests/test_benchmark_scoring.py:4`

**Step 1: 確認 import**

如果 `TERMINOLOGY_RULES` 需要在測試中引用（例如 `test_all_table_entries_applied` 改為遍歷 rules），更新 import：

```python
from benchmark_llm import score_terminology, score_preservation, score_punctuation, call_llm, generate_report, PROMPTS, DEFAULT_PROMPT, apply_terminology_regex, run_two_layer_benchmark, TERMINOLOGY_RULES
```

**Step 2: 跑測試確認**

Run: `cd /Users/fredchu/dev/verbatim-flow && python -m pytest scripts/tests/test_benchmark_scoring.py -v`

Expected: 全部 PASS

**Step 3: Commit（如果有變更）**

```bash
git add scripts/tests/test_benchmark_scoring.py
git commit -m "test: update imports for TERMINOLOGY_RULES"
```
