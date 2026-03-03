#!/usr/bin/env python3
"""LLM ASR Post-Processing Benchmark Tool."""

import re
from difflib import SequenceMatcher

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
    return "".join(ch for ch in text if ch not in PUNCTUATION_CHARS)


def _strip_spaces(text: str) -> str:
    return re.sub(r"\s+", "", text)


def _apply_terminology_removals(text: str, terminology: list[str]) -> str:
    result = text
    for item in terminology:
        if "→" in item:
            wrong, correct = item.split("→", 1)
            result = result.replace(wrong.strip(), "")
            result = result.replace(correct.strip(), "")
        else:
            result = result.replace(item.strip(), "")
    return result


def score_terminology(output: str, corrections: list[str]) -> float:
    if not corrections:
        return 100.0
    found = sum(1 for term in corrections if term in output)
    return round(found / len(corrections) * 100, 2)


def score_preservation(
    input_text: str, output_text: str, terminology: list[str]
) -> float:
    clean_input = _strip_spaces(_strip_punctuation(
        _apply_terminology_removals(input_text, terminology)
    ))
    clean_output = _strip_spaces(_strip_punctuation(
        _apply_terminology_removals(output_text, terminology)
    ))
    if not clean_input and not clean_output:
        return 100.0
    matcher = SequenceMatcher(None, clean_input, clean_output)
    edits = sum(
        max(j2 - j1, i2 - i1)
        for tag, i1, i2, j1, j2 in matcher.get_opcodes()
        if tag != "equal"
    )
    return max(0.0, round(100 - edits * 5, 2))


def score_punctuation(expected: str, output: str) -> tuple[float, float, float]:
    def _get_punctuation_positions(text: str) -> set[tuple[int, str]]:
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
