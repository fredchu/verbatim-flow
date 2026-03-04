# Regex 術語替換改進設計

> Date: 2026-03-04
> Status: Approved
> Branch: feat/breeze-asr
> 前置：兩層管線已驗證（bert+regex 加權 87.2），術語替換目前用 `str.replace`

## 問題

`apply_terminology_regex()` 使用 `str.replace()`，缺乏 word boundary、大小寫容錯、空格容錯、變體合併能力。25 條規則中有多條可合併。

## 設計決策

| 決策 | 選擇 | 理由 |
|------|------|------|
| 大小寫策略 | 統一固定值 | ASR 輸出大小寫不可靠，統一最合理 |
| 規則格式 | Python list of tuples | 清晰、type-safe、YAGNI（不做外部檔案） |
| 測試策略 | 更新舊測試 + 加新測試 | 確保遷移正確 + 驗證新行為 |
| 方案 | 最小改動（方案 A） | 風險低，規則 1:1 對應，不過度抽象 |

## 資料結構

`TERMINOLOGY_TABLE` 純文字 → `TERMINOLOGY_RULES` list of tuples：

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

25 條 → 20 條（合併 5 組變體）。

## 函式實作

```python
def apply_terminology_regex(text: str) -> str:
    """Apply terminology corrections using regex patterns."""
    sorted_rules = sorted(TERMINOLOGY_RULES, key=lambda r: len(r[0]), reverse=True)
    for pattern, replacement, flags in sorted_rules:
        text = re.sub(pattern, replacement, text, flags=flags)
    return text
```

函式簽名不變，callers 零影響。

## 測試計畫

更新現有 4 個 tests + 新增 ~6 個 tests：

| Test | 驗證重點 |
|------|---------|
| `test_ignorecase` | `git hub` / `GIT HUB` → `GitHub` |
| `test_word_boundary_protection` | `GitHub` 不被規則拆開 |
| `test_multi_space_tolerance` | `Chat  GPT`（雙空格）→ `ChatGPT` |
| `test_variant_merge` | `Superpower` / `Super powers` → `Superpowers` |
| `test_chinese_no_boundary_issue` | 中文規則在句子中正常運作 |
| `test_combined_chinese_english` | 混合中英多規則同時生效 |

## 驗證計畫

1. `pytest scripts/tests/test_benchmark_scoring.py -v` 全綠
2. `python scripts/benchmark_llm.py --mode bert+regex` 加權 ≥ 87.2
3. 人工抽查 20 個 test cases 輸出

## 變更範圍

| 檔案 | 變更 |
|------|------|
| `scripts/benchmark_llm.py` | `TERMINOLOGY_TABLE` → `TERMINOLOGY_RULES`，函式改用 `re.sub` |
| `scripts/tests/test_benchmark_scoring.py` | 更新 4 tests + 新增 ~6 tests |
