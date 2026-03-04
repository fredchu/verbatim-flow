# Production ASR 後處理整合設計

> Date: 2026-03-04
> Status: Approved
> Branch: feat/breeze-asr
> 前置：sherpa-onnx 標點模型已驗證（benchmark 加權 87.2），regex 術語替換已改進

## 目標

把 sherpa-onnx 標點恢復 + regex 術語替換整合進 VerbatimFlow production app，對所有 ASR 引擎生效。

## 設計決策

| 決策 | 選擇 | 理由 |
|------|------|------|
| 方案 | 獨立 Python script（方案 A） | 跟現有 Whisper/Qwen3 的 Process 呼叫模式一致 |
| 術語替換 | 合併到 Python 端 | Python regex 更強大（\b + IGNORECASE + ASCII） |
| ASR scope | 全部引擎都過 | 統一邏輯，已有標點的文字通過 sherpa-onnx 不會變差 |
| 模型打包 | 首次使用時自動下載 | 跟 Qwen3 ASR 機制一致，不膨脹 app bundle |
| Pipeline 位置 | ASR raw → Python → TextGuard → ... | 標點恢復在最前面，後續都能處理帶標點文字 |
| Fallback | 失敗時 fallback 到 raw text + log | 跟 ClarifyRewriter 的 fallback 邏輯一致 |
| TERMINOLOGY_RULES | 提取到共用 terminology.py | benchmark 和 postprocess 共用 |

## Pipeline 變更

### Before

```
ASR raw text
  → TextGuard.apply()
  → TerminologyDictionary.applyReplacements()
  → MixedLanguageEnhancer.apply()
  → [optional] ClarifyRewriter
  → TextInjector.insert()
```

### After

```
ASR raw text
  → [NEW] PunctuationPostProcessor.process()  ← Python: 標點 + OpenCC + 術語
  → TextGuard.apply()
  → TerminologyDictionary.applyReplacements()  ← 保留，使用者自訂規則仍生效
  → MixedLanguageEnhancer.apply()
  → [optional] ClarifyRewriter
  → TextInjector.insert()
```

## Python script: `postprocess_asr.py`

### CLI interface

```
stdin: raw ASR text (UTF-8)
stdout: processed text (UTF-8)
stderr: log/error messages
```

```bash
echo "我在Git Hub上面開了一個新的Codex專案" | python postprocess_asr.py --language zh-Hant
# stdout: 我在GitHub上面開了一個新的Codex專案。
```

### 參數

| 參數 | 說明 | 預設 |
|------|------|------|
| `--language` | `zh-Hant` / `zh-Hans` / `en` | `zh-Hant` |
| `--no-punctuation` | 跳過標點恢復 | off |
| `--no-terminology` | 跳過術語替換 | off |
| `--model-dir` | sherpa-onnx 模型目錄 | `~/Library/Application Support/VerbatimFlow/models/` |

### 處理流程

```
stdin raw text
  → sherpa-onnx 標點恢復（除非 --no-punctuation）
  → OpenCC s2t（只在 zh-Hant 時）
  → TERMINOLOGY_RULES regex 替換（除非 --no-terminology）
  → stdout
```

### 模型自動下載

複用 benchmark_punctuation.py 的 `_ensure_model()` 邏輯，model 目錄改到 `~/Library/Application Support/VerbatimFlow/models/`。

### 模型存放位置

```
~/Library/Application Support/VerbatimFlow/models/
  └── sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8/
      └── model.int8.onnx  (76MB)
```

## Swift 端: `PunctuationPostProcessor.swift`

```swift
enum PunctuationPostProcessor {
    static func process(text: String, language: String) throws -> String
}
```

- Process 呼叫 postprocess_asr.py
- stdin 寫入 raw text，讀 stdout
- Timeout: 10 秒
- 失敗時 throw，caller fallback to raw text

### Fallback

```swift
let processed: String
do {
    processed = try PunctuationPostProcessor.process(text: raw, language: localeIdentifier)
    emit("[punctuation] post-processing applied")
} catch {
    processed = raw
    emit("[punctuation] post-processing failed, fallback to raw: \(error)")
}
```

### 失敗場景

| 場景 | 行為 |
|------|------|
| Python 不存在 / venv 壞了 | throw → fallback to raw |
| 首次下載模型中 | 正常等待（可能 30s+） |
| 下載失敗（無網路） | throw → fallback to raw |
| Python crash / 非零 exit code | throw → fallback to raw，log stderr |
| Timeout（10s） | kill → throw → fallback to raw |
| 輸出為空 | 視為失敗 → fallback to raw |

## 檔案變更範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| `apps/mac-client/python/scripts/postprocess_asr.py` | 新建 | CLI: 標點 + OpenCC + 術語 |
| `apps/mac-client/python/scripts/terminology.py` | 新建 | TERMINOLOGY_RULES 共用模組 |
| `apps/mac-client/Sources/.../PunctuationPostProcessor.swift` | 新建 | Process wrapper |
| `apps/mac-client/Sources/.../AppController.swift` | 修改 | commitTranscript() 加入呼叫 |
| `apps/mac-client/Sources/.../SpeechTranscriber.swift` | 修改 | 提取 locatePythonScript/resolvePythonExecutable 為共用 |
| `apps/mac-client/python/scripts/test_postprocess_asr.py` | 新建 | Python 端測試 |
| `scripts/benchmark_llm.py` | 修改 | import terminology.py |

### 不動的

- TerminologyDictionary.swift — 保留使用者自訂規則
- TextGuard.swift — 不動
- MenuBarApp.swift — 不加 UI toggle
- CLIConfig.swift — 不加新 enum
- build-native-app.sh — python/scripts/ 已自動包含

## 依賴

Python: sherpa_onnx, opencc, re (全部已在 venv 中)。不需要新 pip install。
