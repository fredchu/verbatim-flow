# Production ASR 後處理整合 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把 sherpa-onnx 標點恢復 + regex 術語替換整合進 VerbatimFlow app，對所有 ASR 引擎生效。

**Architecture:** 新建 Python CLI script `postprocess_asr.py`（stdin→stdout），由 Swift 端 `PunctuationPostProcessor` 透過 `Process` 呼叫。插在 ASR raw text → TextGuard 之間。共用術語規則提取到 `terminology.py` 模組。

**Tech Stack:** Python 3 (sherpa_onnx, opencc, re), Swift 5.9 (Process, Pipe)

**Design doc:** `docs/plans/2026-03-04-production-postprocess-design.md`

---

### Task 1: 建立 `terminology.py` 共用模組

**Files:**
- Create: `apps/mac-client/python/scripts/terminology.py`
- Create: `apps/mac-client/python/tests/test_terminology.py`

**Step 1: 寫 terminology.py 測試**

```python
# apps/mac-client/python/tests/test_terminology.py
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

from terminology import TERMINOLOGY_RULES, apply_terminology_regex


class TestTerminology:
    def test_rules_exist(self):
        assert len(TERMINOLOGY_RULES) == 20

    def test_basic_replacement(self):
        result = apply_terminology_regex("使用歐拉瑪來跑模型")
        assert result == "使用Ollama來跑模型"

    def test_ignorecase(self):
        result = apply_terminology_regex("用 git hub 管理")
        assert "GitHub" in result

    def test_word_boundary(self):
        result = apply_terminology_regex("上傳到GitHub吧")
        assert result == "上傳到GitHub吧"

    def test_chinese_english_mixed(self):
        result = apply_terminology_regex("用歐拉瑪的work flow跑Chat GPT")
        assert "Ollama" in result
        assert "workflow" in result
        assert "ChatGPT" in result
```

**Step 2: 跑測試確認紅燈**

Run: `cd /Users/fredchu/dev/verbatim-flow && python -m pytest apps/mac-client/python/tests/test_terminology.py -v`

Expected: FAIL (module not found)

**Step 3: 建立 terminology.py**

從 `scripts/benchmark_llm.py` 提取 `TERMINOLOGY_RULES`、`_SORTED_RULES`、`apply_terminology_regex()` 到新檔案：

```python
# apps/mac-client/python/scripts/terminology.py
"""Shared ASR terminology correction rules."""

import re

TERMINOLOGY_RULES = [
    # (pattern, replacement, flags)
    # NOTE: English patterns use re.ASCII so that \b treats only ASCII
    # alphanumerics as word characters, allowing correct matching at
    # Chinese-English boundaries (e.g. "Code的" or "的work").

    # --- 英文術語：\b + IGNORECASE + ASCII ---
    (r'\bGit\s+Hub\b', 'GitHub', re.IGNORECASE | re.ASCII),
    (r'\bOpen\s+AI\b', 'OpenAI', re.IGNORECASE | re.ASCII),
    (r'\bChat\s+GPT\b', 'ChatGPT', re.IGNORECASE | re.ASCII),
    (r'\bOpen\s+CC\b', 'OpenCC', re.IGNORECASE | re.ASCII),
    (r'\bCloud\s+Code\b', 'Claude Code', re.IGNORECASE | re.ASCII),
    (r'\bSuper\s*powers?\b', 'Superpowers', re.IGNORECASE | re.ASCII),
    (r'\bw(?:alk|ork)\s+flow\b', 'workflow', re.IGNORECASE | re.ASCII),
    (r'\bLIM\s+Studio\b', 'LM Studio', re.IGNORECASE | re.ASCII),
    (r'\bEmerald\s+X\b', 'MLX', re.IGNORECASE | re.ASCII),
    (r'\bM2X\b', 'MLX', re.ASCII),
    (r'\bComet\b', 'Commit', re.ASCII),
    (r'\bForced\s+Aligner\b', 'ForcedAligner', re.IGNORECASE | re.ASCII),

    # ASR 音譯模糊匹配
    (r'\bBri[sc]e\s+ASR\b', 'Breeze ASR', re.IGNORECASE | re.ASCII),
    (r'\bBruce\s+ASR\b', 'Breeze ASR', re.IGNORECASE | re.ASCII),
    (r'\bQu[ai]nt\s*3\b', 'Qwen3', re.IGNORECASE | re.ASCII),
    (r'\bQuant\s*3\s*8\s*B\b', 'Qwen3 8B', re.IGNORECASE | re.ASCII),

    # --- 中文音譯：無 \b ---
    (r'歐拉瑪', 'Ollama', 0),
    (r'偷坑', 'token', 0),
    (r'[B逼]肉', 'BROLL', 0),
    (r'集聚', '級距', 0),
]

# Pre-sorted by pattern length (longest first) for specificity
_SORTED_RULES = sorted(TERMINOLOGY_RULES, key=lambda r: len(r[0]), reverse=True)


def apply_terminology_regex(text: str) -> str:
    """Apply terminology corrections using regex patterns."""
    for pattern, replacement, flags in _SORTED_RULES:
        text = re.sub(pattern, replacement, text, flags=flags)
    return text
```

**Step 4: 跑測試確認綠燈**

Run: `cd /Users/fredchu/dev/verbatim-flow && python -m pytest apps/mac-client/python/tests/test_terminology.py -v`

Expected: ALL PASS

**Step 5: Commit**

```bash
cd /Users/fredchu/dev/verbatim-flow
git add apps/mac-client/python/scripts/terminology.py apps/mac-client/python/tests/test_terminology.py
git commit -m "feat: extract shared terminology.py module"
```

---

### Task 2: 更新 benchmark_llm.py import terminology.py

**Files:**
- Modify: `scripts/benchmark_llm.py:16-72`

**Step 1: 修改 benchmark_llm.py**

刪除 `TERMINOLOGY_RULES`、`_SORTED_RULES`、`apply_terminology_regex()` 的本地定義，改為 import。

由於 `scripts/` 和 `apps/mac-client/python/scripts/` 是不同目錄，用 sys.path 加入：

```python
# 在 benchmark_llm.py 開頭的 import 區塊加入：
import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0, str(_Path(__file__).resolve().parent.parent / "apps" / "mac-client" / "python" / "scripts"))

from terminology import TERMINOLOGY_RULES, apply_terminology_regex
```

保留 `_pattern_to_readable()` 和 `TERMINOLOGY_TABLE`（這兩個只有 benchmark 用）。

刪除原本的 `TERMINOLOGY_RULES` 定義（lines 16-47）、`_SORTED_RULES`（line 67）、`apply_terminology_regex()`（lines 70-73）。

**Step 2: 跑既有 benchmark 測試確認不壞**

Run: `cd /Users/fredchu/dev/verbatim-flow && python -m pytest scripts/tests/test_benchmark_scoring.py -v`

Expected: ALL 28 PASS

**Step 3: Commit**

```bash
cd /Users/fredchu/dev/verbatim-flow
git add scripts/benchmark_llm.py
git commit -m "refactor: benchmark_llm imports from shared terminology.py"
```

---

### Task 3: 建立 `postprocess_asr.py` Python script

**Files:**
- Create: `apps/mac-client/python/scripts/postprocess_asr.py`
- Create: `apps/mac-client/python/tests/test_postprocess_asr.py`

**Step 1: 寫 postprocess_asr.py 測試**

```python
# apps/mac-client/python/tests/test_postprocess_asr.py
import subprocess
import sys
import os

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "scripts", "postprocess_asr.py")
PYTHON = sys.executable


def run_postprocess(text: str, args: list[str] | None = None) -> str:
    """Helper: run postprocess_asr.py with stdin text, return stdout."""
    cmd = [PYTHON, SCRIPT] + (args or [])
    result = subprocess.run(cmd, input=text, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"stderr: {result.stderr}"
    return result.stdout.strip()


class TestPostprocessCLI:
    def test_punctuation_and_terminology(self):
        """Full pipeline: punctuation + terminology."""
        result = run_postprocess("我在Git Hub上面開了一個新的專案")
        assert "GitHub" in result
        # sherpa-onnx should have added some punctuation
        assert any(c in result for c in "，。！？；：、")

    def test_no_punctuation_flag(self):
        """--no-punctuation skips punctuation, still does terminology."""
        result = run_postprocess("用歐拉瑪跑模型", ["--no-punctuation"])
        assert "Ollama" in result
        # Should not have added punctuation to this short text
        # (but terminology should still work)

    def test_no_terminology_flag(self):
        """--no-terminology skips terminology, still does punctuation."""
        result = run_postprocess("用歐拉瑪跑模型", ["--no-terminology"])
        assert "歐拉瑪" in result  # NOT replaced

    def test_empty_input(self):
        result = run_postprocess("")
        assert result == ""

    def test_zh_hans_no_opencc(self):
        """zh-Hans should NOT convert to traditional."""
        result = run_postprocess("用欧拉玛跑模型", ["--language", "zh-Hans", "--no-punctuation"])
        # Should not convert simplified to traditional
        # (OpenCC s2t should be skipped)
        assert "Ollama" not in result or "欧" not in result  # won't match 歐拉瑪

    def test_stdin_stdout_contract(self):
        """Verify stdin/stdout contract works."""
        result = run_postprocess("今天天氣很好", ["--no-punctuation", "--no-terminology"])
        assert result == "今天天氣很好"
```

**Step 2: 跑測試確認紅燈**

Run: `cd /Users/fredchu/dev/verbatim-flow && /Users/fredchu/dev/verbatim-flow/apps/mac-client/python/.venv/bin/python -m pytest apps/mac-client/python/tests/test_postprocess_asr.py -v`

Expected: FAIL (script not found)

**Step 3: 建立 postprocess_asr.py**

```python
#!/usr/bin/env python3
"""ASR post-processing: punctuation restoration + terminology correction.

Usage:
    echo "raw asr text" | python postprocess_asr.py [--language zh-Hant] [--no-punctuation] [--no-terminology]

stdin: raw ASR text (UTF-8)
stdout: processed text (UTF-8)
stderr: log/error messages
"""

import argparse
import sys
import tarfile
import time
import urllib.request
from pathlib import Path

# Model configuration
MODEL_NAME = "sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8"
DOWNLOAD_URL = (
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/"
    "punctuation-models/{}.tar.bz2"
)


def _default_model_dir() -> Path:
    """~/Library/Application Support/VerbatimFlow/models/"""
    home = Path.home()
    return home / "Library" / "Application Support" / "VerbatimFlow" / "models"


def _ensure_model(model_dir: Path) -> Path:
    """Download and extract the punctuation model if not present."""
    model_file = model_dir / MODEL_NAME / "model.int8.onnx"
    if model_file.exists():
        return model_file
    model_dir.mkdir(parents=True, exist_ok=True)
    url = DOWNLOAD_URL.format(MODEL_NAME)
    archive_path = model_dir / f"{MODEL_NAME}.tar.bz2"
    print(f"Downloading punctuation model from {url} ...", file=sys.stderr)
    urllib.request.urlretrieve(url, archive_path)
    print(f"Extracting to {model_dir} ...", file=sys.stderr)
    with tarfile.open(archive_path, "r:bz2") as tar:
        tar.extractall(path=model_dir, filter="data")
    archive_path.unlink()
    if not model_file.exists():
        raise FileNotFoundError(f"Model file not found after extraction: {model_file}")
    size_mb = model_file.stat().st_size / 1e6
    print(f"Model ready: {model_file} ({size_mb:.0f} MB)", file=sys.stderr)
    return model_file


def _add_punctuation(text: str, model_dir: Path, language: str) -> str:
    """Add punctuation using sherpa-onnx, optionally convert to Traditional Chinese."""
    import sherpa_onnx
    from opencc import OpenCC

    model_path = str(_ensure_model(model_dir))
    config = sherpa_onnx.OfflinePunctuationConfig(
        model=sherpa_onnx.OfflinePunctuationModelConfig(
            ct_transformer=model_path,
        ),
    )
    punct = sherpa_onnx.OfflinePunctuation(config)
    result = punct.add_punctuation(text)

    if language.startswith("zh-Hant") or language == "zh":
        cc = OpenCC("s2t")
        result = cc.convert(result)

    return result


def _apply_terminology(text: str) -> str:
    """Apply terminology corrections."""
    from terminology import apply_terminology_regex
    return apply_terminology_regex(text)


def main():
    parser = argparse.ArgumentParser(description="ASR post-processing")
    parser.add_argument("--language", default="zh-Hant",
                        help="Language: zh-Hant, zh-Hans, en (default: zh-Hant)")
    parser.add_argument("--no-punctuation", action="store_true",
                        help="Skip punctuation restoration")
    parser.add_argument("--no-terminology", action="store_true",
                        help="Skip terminology correction")
    parser.add_argument("--model-dir", type=Path, default=None,
                        help="Model directory (default: ~/Library/Application Support/VerbatimFlow/models/)")
    args = parser.parse_args()

    model_dir = args.model_dir or _default_model_dir()

    text = sys.stdin.read().strip()
    if not text:
        print("", end="")
        sys.exit(0)

    start = time.time()

    if not args.no_punctuation:
        text = _add_punctuation(text, model_dir, args.language)

    if not args.no_terminology:
        text = _apply_terminology(text)

    elapsed = time.time() - start
    print(f"Post-processing done in {elapsed:.3f}s", file=sys.stderr)

    print(text, end="")


if __name__ == "__main__":
    main()
```

**Step 4: 跑測試確認綠燈**

Run: `cd /Users/fredchu/dev/verbatim-flow && /Users/fredchu/dev/verbatim-flow/apps/mac-client/python/.venv/bin/python -m pytest apps/mac-client/python/tests/test_postprocess_asr.py -v`

Expected: ALL PASS（需要 venv Python 因為依賴 sherpa_onnx）

**Step 5: Commit**

```bash
cd /Users/fredchu/dev/verbatim-flow
git add apps/mac-client/python/scripts/postprocess_asr.py apps/mac-client/python/tests/test_postprocess_asr.py
git commit -m "feat: add postprocess_asr.py CLI script"
```

---

### Task 4: 提取 Swift Python utility 為共用函式

**Files:**
- Create: `apps/mac-client/Sources/VerbatimFlow/PythonScriptRunner.swift`
- Modify: `apps/mac-client/Sources/VerbatimFlow/SpeechTranscriber.swift:495-1024`

**Step 1: 建立 PythonScriptRunner.swift**

把 `SpeechTranscriber` 的 `resolveScript(named:)`、`resolvePythonExecutable(scriptURL:)`、`runSubprocess(_:outputPipe:errorPipe:)` 提取到新的共用 enum：

```swift
// apps/mac-client/Sources/VerbatimFlow/PythonScriptRunner.swift
import Foundation

enum PythonScriptRunner {
    /// Locate a Python script by name, searching source tree and bundle paths.
    static func resolveScript(named filename: String) -> URL? {
        // 完整複製 SpeechTranscriber.resolveScript(named:) 的實作
        // (lines 947-986)
    }

    /// Find the Python executable (venv preferred, system fallback).
    static func resolvePythonExecutable(scriptURL: URL) -> URL? {
        // 完整複製 SpeechTranscriber.resolvePythonExecutable(scriptURL:) 的實作
        // (lines 988-1024)
    }

    /// Run a subprocess, draining stdout/stderr to avoid pipe buffer deadlock.
    static func runSubprocess(
        _ process: Process,
        outputPipe: Pipe,
        errorPipe: Pipe
    ) throws -> (stdout: String, stderr: String) {
        // 完整複製 SpeechTranscriber.runSubprocess 的實作
        // (lines 495-535)
    }
}
```

**Step 2: 修改 SpeechTranscriber.swift**

把原本的三個 private static 函式改為呼叫 `PythonScriptRunner`：

```swift
// 在 SpeechTranscriber 中，把：
//   private nonisolated static func resolveScript(named:) -> URL?
//   private nonisolated static func resolvePythonExecutable(scriptURL:) -> URL?
//   private nonisolated static func runSubprocess(...) throws -> (...)
// 全部刪除，改為：

private nonisolated static func resolveScript(named filename: String) -> URL? {
    PythonScriptRunner.resolveScript(named: filename)
}

private nonisolated static func resolvePythonExecutable(scriptURL: URL) -> URL? {
    PythonScriptRunner.resolvePythonExecutable(scriptURL: scriptURL)
}

private nonisolated static func runSubprocess(
    _ process: Process,
    outputPipe: Pipe,
    errorPipe: Pipe
) throws -> (stdout: String, stderr: String) {
    try PythonScriptRunner.runSubprocess(process, outputPipe: outputPipe, errorPipe: errorPipe)
}
```

**Step 3: Build 確認編譯通過**

Run: `cd /Users/fredchu/dev/verbatim-flow && swift build 2>&1 | tail -5`

Expected: Build succeeded

**Step 4: Commit**

```bash
cd /Users/fredchu/dev/verbatim-flow
git add apps/mac-client/Sources/VerbatimFlow/PythonScriptRunner.swift apps/mac-client/Sources/VerbatimFlow/SpeechTranscriber.swift
git commit -m "refactor: extract PythonScriptRunner from SpeechTranscriber"
```

---

### Task 5: 建立 `PunctuationPostProcessor.swift`

**Files:**
- Create: `apps/mac-client/Sources/VerbatimFlow/PunctuationPostProcessor.swift`
- Modify: `apps/mac-client/Sources/VerbatimFlow/AppError.swift`

**Step 1: 在 AppError 加入新 case**

在 `apps/mac-client/Sources/VerbatimFlow/AppError.swift` 加入：

```swift
case postprocessScriptNotFound
case postprocessFailed(String)
```

及對應的 `localizedDescription`：

```swift
case .postprocessScriptNotFound:
    return "Post-processing script (postprocess_asr.py) not found."
case .postprocessFailed(let details):
    return "Post-processing failed: \(details)"
```

**Step 2: 建立 PunctuationPostProcessor.swift**

```swift
// apps/mac-client/Sources/VerbatimFlow/PunctuationPostProcessor.swift
import Foundation

enum PunctuationPostProcessor {
    private static let timeoutSeconds: Double = 60  // generous for first-time model download

    /// Run sherpa-onnx punctuation + terminology correction via Python script.
    /// Returns processed text, or throws on failure.
    static func process(text: String, language: String) throws -> String {
        guard !text.isEmpty else { return "" }

        guard let scriptURL = PythonScriptRunner.resolveScript(named: "postprocess_asr.py") else {
            throw AppError.postprocessScriptNotFound
        }

        guard let pythonURL = PythonScriptRunner.resolvePythonExecutable(scriptURL: scriptURL) else {
            throw AppError.pythonRuntimeNotFound
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = pythonURL
        process.arguments = [
            scriptURL.path,
            "--language", language
        ]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Write stdin
        let inputData = text.data(using: .utf8) ?? Data()
        inputPipe.fileHandleForWriting.write(inputData)
        inputPipe.fileHandleForWriting.closeFile()

        let (outputText, errorText) = try PythonScriptRunner.runSubprocess(
            process,
            outputPipe: outputPipe,
            errorPipe: errorPipe
        )

        if process.terminationStatus != 0 {
            let details = errorText.isEmpty ? outputText : errorText
            throw AppError.postprocessFailed(details)
        }

        let result = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? text : result
    }
}
```

**Step 3: Build 確認編譯通過**

Run: `cd /Users/fredchu/dev/verbatim-flow && swift build 2>&1 | tail -5`

Expected: Build succeeded

**Step 4: Commit**

```bash
cd /Users/fredchu/dev/verbatim-flow
git add apps/mac-client/Sources/VerbatimFlow/PunctuationPostProcessor.swift apps/mac-client/Sources/VerbatimFlow/AppError.swift
git commit -m "feat: add PunctuationPostProcessor Swift wrapper"
```

---

### Task 6: 整合進 AppController.commitTranscript()

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/AppController.swift:551-584`

**Step 1: 在 TextGuard 之前插入 Python 後處理**

在 `commitTranscript()` 中，找到 line 577：

```swift
let guarded = TextGuard(mode: commandParsed.effectiveMode).apply(raw: commandParsed.content)
```

在這行之前插入：

```swift
        // --- Punctuation + terminology post-processing (Python) ---
        let postprocessedContent: String
        do {
            postprocessedContent = try PunctuationPostProcessor.process(
                text: commandParsed.content,
                language: localeIdentifier
            )
            emit("[punctuation] post-processing applied")
        } catch {
            postprocessedContent = commandParsed.content
            emit("[punctuation] post-processing failed, fallback to raw: \(error)")
        }

        let guarded = TextGuard(mode: commandParsed.effectiveMode).apply(raw: postprocessedContent)
```

同時刪除原本的：

```swift
        let guarded = TextGuard(mode: commandParsed.effectiveMode).apply(raw: commandParsed.content)
```

**Step 2: Build 確認編譯通過**

Run: `cd /Users/fredchu/dev/verbatim-flow && swift build 2>&1 | tail -5`

Expected: Build succeeded

**Step 3: Commit**

```bash
cd /Users/fredchu/dev/verbatim-flow
git add apps/mac-client/Sources/VerbatimFlow/AppController.swift
git commit -m "feat: integrate punctuation post-processing into ASR pipeline"
```

---

### Task 7: 完整驗證

**Files:** 無變更，只跑驗證

**Step 1: 跑所有 Python 測試**

Run: `cd /Users/fredchu/dev/verbatim-flow && /Users/fredchu/dev/verbatim-flow/apps/mac-client/python/.venv/bin/python -m pytest apps/mac-client/python/tests/ -v`

Expected: ALL PASS

**Step 2: 跑 benchmark 測試**

Run: `cd /Users/fredchu/dev/verbatim-flow && python -m pytest scripts/tests/test_benchmark_scoring.py -v`

Expected: ALL 28 PASS

**Step 3: Build full app**

Run: `cd /Users/fredchu/dev/verbatim-flow && ./scripts/build-native-app.sh`

Expected: Build succeeded，app 安裝到 /Applications

**Step 4: 手動驗收**

1. 開啟 VerbatimFlow app
2. 用任一 ASR 引擎錄一段中文
3. 確認輸出有標點符號
4. 確認術語替換生效
5. 檢查 log 視窗有 `[punctuation] post-processing applied`

**Step 5: 跑 benchmark 確認不退步**

Run: `cd /Users/fredchu/dev/verbatim-flow/scripts && /Users/fredchu/dev/verbatim-flow/apps/mac-client/python/.venv/bin/python benchmark_llm.py --mode bert+regex`

Expected: 加權 ≥ 87.2
