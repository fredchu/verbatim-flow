# LM Studio Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 將 VerbatimFlow 的 LLM 後端從 Ollama 切換至 LM Studio，統一使用 OpenAI-compatible `/v1/chat/completions` API 格式。

**Architecture:** 兩個分支各自改動：`feat/breeze-asr` 改 Python `_add_punctuation()`，`feat/local-rewrite` 更新設計文件。統一使用泛化 env vars (`VERBATIMFLOW_LLM_BASE_URL`, `VERBATIMFLOW_LLM_MODEL`)，新增 `<think>` strip 安全網。

**Tech Stack:** Python 3 (urllib), OpenAI Chat Completions API format, LM Studio (Qwen3-VL 8B MLX)

---

### Task 1: Update `_add_punctuation()` tests for OpenAI format (feat/breeze-asr)

**Files:**
- Modify: `apps/mac-client/python/tests/test_mlx_whisper_transcriber.py:79-147`

**Step 1: Write updated tests with OpenAI response format and new env vars**

Replace the `TestAddPunctuation` class (lines 79-147) with:

```python
class TestAddPunctuation(unittest.TestCase):
    @patch("verbatim_flow.mlx_whisper_transcriber.urllib.request.urlopen")
    def test_returns_punctuated_text(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "choices": [{"message": {"content": "好，所以我們繼續。"}}]
        }).encode()
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        result = _add_punctuation("好所以我們繼續")
        self.assertEqual(result, "好，所以我們繼續。")

    @patch("verbatim_flow.mlx_whisper_transcriber.urllib.request.urlopen")
    def test_fallback_on_error(self, mock_urlopen):
        mock_urlopen.side_effect = Exception("connection refused")

        result = _add_punctuation("好所以我們繼續")
        self.assertEqual(result, "好所以我們繼續")

    @patch("verbatim_flow.mlx_whisper_transcriber.urllib.request.urlopen")
    def test_sends_correct_payload(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "choices": [{"message": {"content": "測試。"}}]
        }).encode()
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        _add_punctuation("測試")

        call_args = mock_urlopen.call_args
        req = call_args[0][0]
        self.assertEqual(req.full_url, "http://localhost:1234/v1/chat/completions")
        payload = json.loads(req.data)
        self.assertEqual(payload["model"], "qwen/qwen3-vl-8b")
        self.assertEqual(payload["stream"], False)
        self.assertEqual(payload["temperature"], 0.1)
        self.assertEqual(payload["max_tokens"], 2048)
        self.assertEqual(payload["messages"][1]["content"], "測試")
        self.assertIn("/no_think", payload["messages"][0]["content"])

    @patch.dict("os.environ", {
        "VERBATIMFLOW_LLM_BASE_URL": "http://myhost:9999",
        "VERBATIMFLOW_LLM_MODEL": "llama3:latest",
    })
    @patch("verbatim_flow.mlx_whisper_transcriber.urllib.request.urlopen")
    def test_respects_env_vars(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "choices": [{"message": {"content": "結果。"}}]
        }).encode()
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        _add_punctuation("結果")

        req = mock_urlopen.call_args[0][0]
        self.assertEqual(req.full_url, "http://myhost:9999/v1/chat/completions")
        payload = json.loads(req.data)
        self.assertEqual(payload["model"], "llama3:latest")

    @patch("verbatim_flow.mlx_whisper_transcriber.urllib.request.urlopen")
    def test_empty_text_returned_as_is(self, mock_urlopen):
        result = _add_punctuation("")
        self.assertEqual(result, "")
        mock_urlopen.assert_not_called()

    @patch("verbatim_flow.mlx_whisper_transcriber.urllib.request.urlopen")
    def test_strips_think_tags_from_response(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "choices": [{"message": {"content": "<think>思考中...</think>好，所以我們繼續。"}}]
        }).encode()
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        result = _add_punctuation("好所以我們繼續")
        self.assertEqual(result, "好，所以我們繼續。")
```

**Step 2: Run tests to verify they fail**

Run: `cd apps/mac-client/python && python -m pytest tests/test_mlx_whisper_transcriber.py::TestAddPunctuation -v`
Expected: FAIL — URL, model, response format all mismatch current implementation.

**Step 3: Commit**

```
test(breeze-asr): update punctuation tests for OpenAI-compatible API format
```

---

### Task 2: Update `_add_punctuation()` implementation (feat/breeze-asr)

**Files:**
- Modify: `apps/mac-client/python/verbatim_flow/mlx_whisper_transcriber.py:87-124`

**Step 1: Add `import re` at the top of the file**

Add `import re` alongside the existing imports (around line 5-8).

**Step 2: Replace `_add_punctuation()` with OpenAI-compatible version**

Replace lines 87-124 with:

```python
def _add_punctuation(text: str) -> str:
    """Add punctuation to unpunctuated Chinese text via OpenAI-compatible LLM API."""
    if not text:
        return text

    import json
    import os

    base_url = os.environ.get("VERBATIMFLOW_LLM_BASE_URL", "http://localhost:1234")
    model = os.environ.get("VERBATIMFLOW_LLM_MODEL", "qwen/qwen3-vl-8b")

    payload = json.dumps({
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": (
                    "你是標點符號專家。請為以下中文語音辨識文字加上適當的全形標點符號"
                    "（，。、？！：；）。只加標點，不改動任何文字內容。"
                    "直接輸出結果，不要解釋。/no_think"
                ),
            },
            {"role": "user", "content": text},
        ],
        "temperature": 0.1,
        "max_tokens": 2048,
        "stream": False,
    }).encode()

    req = urllib.request.Request(
        f"{base_url}/v1/chat/completions",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            result = json.loads(resp.read())
            content = result["choices"][0]["message"]["content"].strip()
            return re.sub(r"<think>[\s\S]*?</think>", "", content).strip()
    except Exception:
        return text  # Fallback: return unpunctuated text
```

**Step 3: Run tests to verify they pass**

Run: `cd apps/mac-client/python && python -m pytest tests/test_mlx_whisper_transcriber.py::TestAddPunctuation -v`
Expected: All 6 tests PASS.

**Step 4: Run full test suite to check no regressions**

Run: `cd apps/mac-client/python && python -m pytest tests/test_mlx_whisper_transcriber.py -v`
Expected: All tests PASS.

**Step 5: Commit**

```
feat(breeze-asr): switch _add_punctuation to OpenAI-compatible API format

- Endpoint: /v1/chat/completions (works with LM Studio and Ollama)
- Env vars: VERBATIMFLOW_LLM_BASE_URL, VERBATIMFLOW_LLM_MODEL
- Default: localhost:1234, qwen/qwen3-vl-8b
- Added <think> tag stripping as /no_think safety net
```

---

### Task 3: Update `_add_punctuation()` docstring (feat/breeze-asr)

**Files:**
- Modify: `apps/mac-client/python/verbatim_flow/mlx_whisper_transcriber.py:88`

**Step 1: Verify the docstring was already updated in Task 2**

The docstring should now read `"""Add punctuation to unpunctuated Chinese text via OpenAI-compatible LLM API."""` — this was included in Task 2's replacement code. If so, skip this task.

**Step 2: Verify the full test suite still passes**

Run: `cd apps/mac-client/python && python -m pytest tests/test_mlx_whisper_transcriber.py -v`
Expected: All tests PASS.

---

### Task 4: Update local-rewrite design doc (feat/local-rewrite)

**Files:**
- Modify: `docs/plans/2026-03-02-local-llm-rewrite-design.md`

**Step 1: Switch to feat/local-rewrite branch**

Run: `git stash && git checkout feat/local-rewrite`

**Step 2: Update the design doc**

Make these replacements in `docs/plans/2026-03-02-local-llm-rewrite-design.md`:

1. Line 41: `LocalRewriter (Ollama API)` → `LocalRewriter (LM Studio / OpenAI API)`
2. Line 62: `HTTP POST to Ollama \`http://localhost:11434/api/chat\`` → `HTTP POST to LM Studio \`http://localhost:1234/v1/chat/completions\` (OpenAI-compatible)`
3. Line 63: `Ollama 相容 OpenAI chat completions 格式` → `相容任何 OpenAI chat completions 端點（LM Studio / Ollama）`
4. Lines 68-81: Replace the API call example:

```json
{
  "model": "qwen/qwen3-vl-8b",
  "messages": [
    {"role": "system", "content": "<system prompt>"},
    {"role": "user", "content": "locale=zh-Hant\n\n<transcribed text>"}
  ],
  "temperature": 0.1,
  "max_tokens": 2048,
  "stream": false
}
```

5. Lines 102-106: Replace env var table:

| 環境變數 | 預設值 | 說明 |
|----------|--------|------|
| `VERBATIMFLOW_LLM_BASE_URL` | `http://localhost:1234` | LLM API 端點 |
| `VERBATIMFLOW_LLM_MODEL` | `qwen/qwen3-vl-8b` | 模型名稱 |

6. Line 117: `Local Rewrite (Ollama)` → `Local Rewrite (LM Studio)`
7. Lines 124-127: Update error messages — replace "Ollama" with "LLM server", "ollama pull" with model download instructions.

**Step 3: Commit**

```
docs(local-rewrite): update design doc for LM Studio migration
```

---

### Task 5: Update local-rewrite implementation plan (feat/local-rewrite)

**Files:**
- Modify: `docs/plans/2026-03-02-local-llm-rewrite-plan.md`

**Step 1: Update the plan doc**

Key replacements throughout the file:

1. Header (lines 5-9): Update goal/architecture/tech stack to reference LM Studio and OpenAI API instead of Ollama.
2. Task 4 — LocalRewriter.swift (lines 125-263): Update the full code listing:
   - `defaultBaseURL` → `"http://localhost:1234"`
   - `defaultModel` → `"qwen/qwen3-vl-8b"`
   - `VERBATIMFLOW_OLLAMA_BASE_URL` → `VERBATIMFLOW_LLM_BASE_URL`
   - `VERBATIMFLOW_LOCAL_REWRITE_MODEL` → `VERBATIMFLOW_LLM_MODEL`
   - URL path: `api/chat` → `v1/chat/completions`
   - Response parsing: `json["message"]` → `json["choices"][0]["message"]`
   - Add `<think>` stripping after extracting content
   - Remove Ollama-specific fields (`keep_alive`, `options.num_predict`) and use top-level `temperature`, `max_tokens`
   - Error messages: "Ollama" → "LLM server", "ollama pull" → generic
3. Task 5 — AppController (line 321): `[local-rewrite] ollama rewrite` → `[local-rewrite] llm rewrite`
4. Task 6 — MenuBarApp (line 363): `"Local Rewrite (Ollama)"` → `"Local Rewrite (LM Studio)"`
5. Task 8 — Manual test (lines 436-466): Remove `ollama pull`, update test commands

**Step 2: Commit**

```
docs(local-rewrite): update implementation plan for LM Studio migration
```

---

### Task 6: Switch back to feat/breeze-asr and verify

**Step 1: Switch back**

Run: `git checkout feat/breeze-asr`

**Step 2: Run full Python test suite**

Run: `cd apps/mac-client/python && python -m pytest tests/ -v`
Expected: All tests PASS.

**Step 3: Manual smoke test (optional)**

If LM Studio is running with `qwen/qwen3-vl-8b` loaded:

```bash
curl -s http://localhost:1234/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen/qwen3-vl-8b","messages":[{"role":"system","content":"你是標點符號專家。請為以下中文語音辨識文字加上適當的全形標點符號（，。、？！：；）。只加標點，不改動任何文字內容。直接輸出結果，不要解釋。/no_think"},{"role":"user","content":"好所以我們繼續討論下一個問題"}],"temperature":0.1,"max_tokens":2048,"stream":false}' | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])"
```

Expected: `好，所以我們繼續討論下一個問題。`（或類似帶標點的輸出）
