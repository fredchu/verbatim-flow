# LM Studio Migration Design

## Overview

將 VerbatimFlow 的 LLM 後端從 Ollama 切換至 LM Studio，統一使用 OpenAI-compatible `/v1/chat/completions` API 格式。

## Background

目前 Ollama (qwen3:8b) 用於兩個功能：
- **Breeze ASR 自動標點**（`feat/breeze-asr`，Python，已實作）
- **Local Rewrite 校正**（`feat/local-rewrite`，Swift，尚未實作）

LM Studio 使用 Qwen3-VL 8B MLX 版本，效能更好（MLX 原生加速）。兩者都支援 OpenAI-compatible API，因此只需切換 base URL 和 response 解析格式。

## Design

### API 格式統一

所有 LLM 呼叫統一使用 OpenAI `/v1/chat/completions` 格式：

**Request**:
```json
POST {base_url}/v1/chat/completions
{
  "model": "qwen/qwen3-vl-8b",
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "..."}
  ],
  "temperature": 0.1,
  "max_tokens": 2048,
  "stream": false
}
```

**Response 解析**:
```
result["choices"][0]["message"]["content"]
```

### `/no_think` 安全網

- 保留 system prompt 末尾的 `/no_think`（對 Qwen3 有效，對 VL 版無害）
- Response 回來後 strip `<think>...</think>` 區塊，確保不漏出思維鏈：
  ```python
  re.sub(r"<think>[\s\S]*?</think>", "", text).strip()
  ```

### 環境變數重命名

| 舊名稱 | 新名稱 | 預設值 |
|---|---|---|
| `VERBATIMFLOW_OLLAMA_BASE_URL` | `VERBATIMFLOW_LLM_BASE_URL` | `http://localhost:1234` |
| `VERBATIMFLOW_LOCAL_REWRITE_MODEL` | `VERBATIMFLOW_LLM_MODEL` | `qwen/qwen3-vl-8b` |

不做向後相容 fallback（兩個功能都還在 feature branch，無已發佈使用者）。

## 各分支改動

### `feat/breeze-asr`（Python）

**`mlx_whisper_transcriber.py` — `_add_punctuation()`**:
1. env var：`VERBATIMFLOW_OLLAMA_BASE_URL` → `VERBATIMFLOW_LLM_BASE_URL`
2. env var：`VERBATIMFLOW_LOCAL_REWRITE_MODEL` → `VERBATIMFLOW_LLM_MODEL`
3. 預設 URL：`http://localhost:11434` → `http://localhost:1234`
4. 預設 model：`qwen3:8b` → `qwen/qwen3-vl-8b`
5. 端點：`{base_url}/api/chat` → `{base_url}/v1/chat/completions`
6. Request body：加 `temperature`, `max_tokens`
7. Response：`result["message"]["content"]` → `result["choices"][0]["message"]["content"]`
8. 新增 strip think regex

**`test_mlx_whisper_transcriber.py`**:
- 更新 env var key 名稱
- 更新 mock response 為 OpenAI 格式

### `feat/local-rewrite`（Swift）

- `LocalRewriter.swift` 尚未建立，直接以新規格設計
- 更新設計文件中的 env var 名稱、URL、response format

## 風險

- **`/no_think` 相容性**：Qwen3-VL 可能不支援 `/no_think`，但 strip think regex 作為安全網可覆蓋此風險
- **LM Studio 未啟動**：與 Ollama 相同，連線失敗時 fallback 回原文（Breeze ASR 標點）或拋錯（Local Rewrite）
