#!/usr/bin/env python3
"""LLM ASR Post-Processing Benchmark Tool."""

import argparse
import json
import re
import time
from datetime import datetime
from difflib import SequenceMatcher
from pathlib import Path

import requests

PUNCTUATION_CHARS = set("，。！？；：、「」『』《》")

TERMINOLOGY_TABLE = """歐拉瑪 → Ollama
Comet → Commit
walk flow → workflow
work flow → workflow
偷坑 → token
B肉 → BROLL
逼肉 → BROLL
Cloud Code → Claude Code
Super power → Superpowers
Super powers → Superpowers
Brise ASR → Breeze ASR
Bruce ASR → Breeze ASR
Brice ASR → Breeze ASR
Quint 3 → Qwen3
Quant 3 → Qwen3
Quant 38B → Qwen3 8B
集聚 → 級距
LIM Studio → LM Studio
Emerald X → MLX
M2X → MLX
Git Hub → GitHub
Open AI → OpenAI
Chat GPT → ChatGPT
Open CC → OpenCC
Forced Aligner → ForcedAligner"""


def apply_terminology_regex(text: str) -> str:
    """Apply terminology corrections using string replacement."""
    result = text
    for line in TERMINOLOGY_TABLE.strip().split("\n"):
        wrong, correct = line.split("→", 1)
        result = result.replace(wrong.strip(), correct.strip())
    return result


PROMPTS = {
    "v1": """你是標點與術語校正器。
規則：
- 只加標點符號（，。！？；：「」），不修改任何文字內容。
- 唯一例外：套用以下術語替換表，將語音誤識別的詞彙修正為正確寫法。
- 不刪字、不加字、不改寫、不潤飾、不合併語句。
- 使用全形標點符號。
- 術語替換：歐拉瑪 → Ollama｜Comet → Commit｜walk flow → workflow｜work flow → workflow｜偷坑 → token｜B肉 → BROLL｜逼肉 → BROLL｜Cloud Code → Claude Code｜Super power → Superpowers｜Super powers → Superpowers｜Brise ASR → Breeze ASR｜Bruce ASR → Breeze ASR｜Brice ASR → Breeze ASR｜Quint 3 → Qwen3｜Quant 3 → Qwen3｜Quant 38B → Qwen3 8B｜集聚 → 級距｜LIM Studio → LM Studio｜Emerald X → MLX｜M2X → MLX
- 僅輸出結果，不要解釋。 /no_think""",

    "v2-fewshot": f"""你必須對語音辨識文字做兩件事：
1. 將錯誤術語替換為正確寫法
2. 加入中文全形標點符號

術語替換表：
{TERMINOLOGY_TABLE}

範例：
輸入：我要用Cloud Code來寫一個work flow自動化Comet和Release的流程
輸出：我要用 Claude Code 來寫一個 workflow，自動化 Commit 和 Release 的流程。

輸入：把逼肉的片段剪出來然後用Open CC轉成繁體
輸出：把 BROLL 的片段剪出來，然後用 OpenCC 轉成繁體。

輸入：用Brise ASR跑Forced Aligner然後匯出SRT字幕檔
輸出：用 Breeze ASR 跑 ForcedAligner，然後匯出 SRT 字幕檔。

只輸出校正結果，不要解釋。 /no_think""",

    "v3-positive": f"""對以下語音轉錄文字執行兩個操作：

操作一：找到並替換這些錯誤術語：
{TERMINOLOGY_TABLE}

操作二：在適當位置加入中文全形標點符號（，。！？；：）。

除了上述兩個操作，不要修改任何其他文字。直接輸出結果。 /no_think""",

    "v4-json": f"""你是語音辨識後處理器。對輸入文字執行術語校正和標點符號插入。

術語替換表：
{TERMINOLOGY_TABLE}

以 JSON 格式回覆，只包含一個 "output" 欄位：
{{"output": "校正後的文字"}}

不要輸出任何其他內容。 /no_think""",

    "v5-term-only": f"""你是術語校正器。
規則：
- 只替換以下術語表中的錯誤詞彙，不修改任何其他文字。
- 不加字、不刪字、不改標點符號、不改寫句子。
- 術語替換表：
{TERMINOLOGY_TABLE}
- 僅輸出結果，不要解釋。 /no_think""",
}

# Default prompt key
DEFAULT_PROMPT = "v1"


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


LM_STUDIO_DEFAULT_URL = "http://localhost:1234"

DEFAULT_MODELS = [
    "qwen3-0.6b-mlx",
    "qwen/qwen3-1.7b",
    "qwen/qwen3-4b",
    "qwen/qwen3-8b",
    "google/gemma-3-4b",
    "microsoft/phi-4-mini-reasoning",
]


def call_llm(
    input_text: str,
    model: str,
    base_url: str = LM_STUDIO_DEFAULT_URL,
    prompt_key: str = DEFAULT_PROMPT,
) -> dict:
    system_prompt = PROMPTS[prompt_key]
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
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

    content = data["choices"][0]["message"]["content"].strip()
    # Strip <think>...</think> blocks from models that ignore /no_think
    content = re.sub(r"<think>.*?</think>", "", content, flags=re.DOTALL).strip()
    # Extract JSON output field for v4-json prompt
    if prompt_key == "v4-json":
        try:
            parsed = json.loads(content)
            content = parsed.get("output", content)
        except (json.JSONDecodeError, TypeError):
            # Try to extract from partial JSON
            m = re.search(r'"output"\s*:\s*"([^"]*)"', content)
            if m:
                content = m.group(1)

    return {
        "content": content,
        "usage": usage,
        "elapsed_s": round(elapsed, 3),
        "tokens_per_sec": round(tokens_per_sec, 1),
    }


def generate_report(results: dict, prompt_key: str = DEFAULT_PROMPT) -> str:
    lines = [
        "# LLM ASR Post-Processing Benchmark",
        f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        f"Prompt: {prompt_key}",
        "",
        "## 綜合排名",
        "| # | 模型 | 術語(40%) | 保留度(30%) | 標點(30%) | 加權總分 | tok/s |",
        "|---|---|---|---|---|---|---|",
    ]

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


def run_benchmark(
    testcases_path: str,
    model: str,
    base_url: str = LM_STUDIO_DEFAULT_URL,
    prompt_key: str = DEFAULT_PROMPT,
) -> dict:
    with open(testcases_path) as f:
        testcases = json.load(f)

    cases = []
    for tc in testcases:
        print(f"  [{tc['id']}] {tc['input'][:40]}...")
        result = call_llm(tc["input"], model=model, base_url=base_url, prompt_key=prompt_key)

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


def main():
    parser = argparse.ArgumentParser(description="LLM ASR Post-Processing Benchmark")
    parser.add_argument(
        "--models", nargs="+",
        help="Model IDs to test (default: all in DEFAULT_MODELS)",
    )
    parser.add_argument(
        "--prompt", nargs="+",
        choices=list(PROMPTS.keys()) + ["all"],
        default=[DEFAULT_PROMPT],
        help=f"Prompt variants to test (default: {DEFAULT_PROMPT})",
    )
    parser.add_argument(
        "--url", default=LM_STUDIO_DEFAULT_URL,
        help=f"LM Studio API URL (default: {LM_STUDIO_DEFAULT_URL})",
    )
    args = parser.parse_args()

    models = args.models or DEFAULT_MODELS
    prompts = list(PROMPTS.keys()) if "all" in args.prompt else args.prompt

    testcases_path = Path(__file__).parent / "benchmark_testcases.json"
    output_dir = Path(__file__).parent / "benchmark_results"
    output_dir.mkdir(exist_ok=True)

    if not testcases_path.exists():
        print(f"Error: {testcases_path} not found")
        return

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    total_combos = len(prompts) * len(models)

    print("=" * 60)
    print("LLM ASR Post-Processing Benchmark")
    print("=" * 60)
    print(f"Test cases: {testcases_path}")
    print(f"LM Studio API: {args.url}")
    print(f"Prompts: {', '.join(prompts)}")
    print(f"Models: {len(models)}")
    for m in models:
        print(f"  - {m}")
    print(f"Total combinations: {total_combos}")
    print()

    combo_idx = 0
    for prompt_key in prompts:
        all_results = {"models": {}}

        print(f"\n{'#'*60}")
        print(f"# Prompt: {prompt_key}")
        print(f"{'#'*60}")

        for model in models:
            combo_idx += 1
            print(f"\n{'='*60}")
            print(f"[{combo_idx}/{total_combos}] {prompt_key} × {model}")
            print(f"{'='*60}")
            try:
                model_results = run_benchmark(
                    str(testcases_path), model=model,
                    base_url=args.url, prompt_key=prompt_key,
                )
                all_results["models"][model] = model_results

                print(f"\n--- {model} 結果 ---")
                print(f"  術語校正率: {model_results['avg_terminology']:.1f}")
                print(f"  文字保留度: {model_results['avg_preservation']:.1f}")
                print(f"  標點 F1:    {model_results['avg_punctuation_f1']:.1f}")
                print(f"  加權總分:   {model_results['avg_weighted']:.1f}")
                print(f"  平均速度:   {model_results['avg_tokens_per_sec']:.0f} tok/s")
            except Exception as e:
                print(f"Error testing {model}: {e}")
                print("跳過此模型，繼續下一個...")
                continue

        if all_results["models"]:
            json_path = output_dir / f"results_{prompt_key}_{timestamp}.json"
            with open(json_path, "w") as f:
                serializable = json.loads(json.dumps(all_results, default=str))
                json.dump(serializable, f, ensure_ascii=False, indent=2)
            print(f"\n原始結果: {json_path}")

            report = generate_report(all_results, prompt_key=prompt_key)
            report_path = output_dir / f"report_{prompt_key}_{timestamp}.md"
            with open(report_path, "w") as f:
                f.write(report)
            print(f"比較報告: {report_path}")
        else:
            print(f"Prompt {prompt_key}: 沒有測試結果。")


if __name__ == "__main__":
    main()
