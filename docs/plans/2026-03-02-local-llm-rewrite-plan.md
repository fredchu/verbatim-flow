# Local LLM Rewrite Mode Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "Local Rewrite (LM Studio)" text guard mode that uses Qwen3 8B via OpenAI-compatible LLM API to rewrite spoken dictation into polished Traditional Chinese written text.

**Architecture:** New `localRewrite` case in `OutputMode` enum, new `LocalRewriter.swift` module calling OpenAI-compatible Chat Completions API (`/v1/chat/completions`), integrated into `AppController.commitTranscript()` alongside existing `ClarifyRewriter`. UI adds a menu item in the Mode submenu.

**Tech Stack:** Swift 5.9, URLSession for HTTP, OpenAI-compatible Chat Completions API (`/v1/chat/completions`), LM Studio, Qwen3 8B model

---

### Task 1: Add `localRewrite` to OutputMode enum

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/CLIConfig.swift:4-8`

**Step 1: Add the new enum case**

In `CLIConfig.swift`, add `localRewrite` to `OutputMode`:

```swift
enum OutputMode: String {
    case raw
    case formatOnly = "format-only"
    case clarify
    case localRewrite = "local-rewrite"
}
```

**Step 2: Update CLI parse help text**

In `CLIConfig.swift:153`, update the mode error message:

```swift
throw ConfigError.invalidValue("--mode", "raw | format-only | clarify | local-rewrite")
```

In `CLIConfig.swift:238` (HelpPrinter), update the usage string to include `local-rewrite`.

**Step 3: Build to verify no compile errors**

Run: `cd apps/mac-client && swift build 2>&1 | tail -20`
Expected: Compile errors in `TextGuard.swift` and `AppController.swift` switch statements (missing case). This is expected — we fix them in the next tasks.

**Step 4: Commit**

```
feat(local-rewrite): add localRewrite case to OutputMode enum
```

---

### Task 2: Handle `localRewrite` in TextGuard

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/TextGuard.swift:17-29`

**Step 1: Add `localRewrite` case to TextGuard.apply()**

The `localRewrite` mode uses the same pre-processing as `clarify` (strip filler words, collapse duplicates). In `TextGuard.swift`, update the switch:

```swift
switch mode {
case .raw:
    return GuardedText(text: trimmedRaw, fellBackToRaw: false)
case .formatOnly:
    let formatted = formatOnlyNormalize(trimmedRaw)
    if semanticallyEquivalent(lhs: trimmedRaw, rhs: formatted) {
        return GuardedText(text: formatted, fellBackToRaw: false)
    }
    return GuardedText(text: trimmedRaw, fellBackToRaw: true)
case .clarify, .localRewrite:
    let clarified = clarifyNormalize(trimmedRaw)
    return GuardedText(text: clarified.isEmpty ? trimmedRaw : clarified, fellBackToRaw: false)
}
```

**Step 2: Build to verify TextGuard compiles**

Run: `cd apps/mac-client && swift build 2>&1 | tail -20`
Expected: Still errors in AppController (missing case for localRewrite) — that's OK.

**Step 3: Commit**

```
feat(local-rewrite): handle localRewrite in TextGuard using clarify pre-processing
```

---

### Task 3: Add `localRewriteFailed` error case

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/AppError.swift`

**Step 1: Add the error case**

Add after `openAIClarifyFailed`:

```swift
case localRewriteFailed(String)
```

**Step 2: Add the description**

Add after the `openAIClarifyFailed` description case:

```swift
case .localRewriteFailed(let details):
    if details.isEmpty {
        return "Local LLM rewrite failed"
    }
    return "Local LLM rewrite failed: \(details)"
```

**Step 3: Commit**

```
feat(local-rewrite): add localRewriteFailed error case
```

---

### Task 4: Create LocalRewriter.swift

**Files:**
- Create: `apps/mac-client/Sources/VerbatimFlow/LocalRewriter.swift`

**Step 1: Write the full LocalRewriter implementation**

```swift
import Foundation

struct LocalRewriteResult: Sendable {
    let text: String
    let model: String
}

enum LocalRewriter {
    private static let defaultBaseURL = "http://localhost:1234"
    private static let defaultModel = "qwen/qwen3-vl-8b"

    static func rewrite(text: String, localeIdentifier: String) throws -> LocalRewriteResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return LocalRewriteResult(text: "", model: "")
        }

        let env = ProcessInfo.processInfo.environment
        let baseURL = env["VERBATIMFLOW_LLM_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? defaultBaseURL
        let model = env["VERBATIMFLOW_LLM_MODEL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? defaultModel

        let systemPrompt = """
            你是 VerbatimFlow 本地校正模式。
            將語音轉錄的口語文字改寫為通順的書面語。
            規則：
            - 保持原意、事實、數字、專有名詞不變。
            - 不添加原文沒有的資訊。
            - 去除口語贅詞（嗯、啊、然後、就是說、對、那個）和明顯重複。
            - 保持與輸入相同的語言（中文維持中文，中英混合維持混合）。
            - 使用台灣繁體中文用語和全形標點符號（，。！？；：）。
            - 僅輸出改寫後的純文字，不要 markdown，不要解釋。 /no_think
            """

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "locale=\(localeIdentifier)\n\n" + trimmed]
            ],
            "stream": false,
            "temperature": 0.1,
            "max_tokens": 2048
        ]

        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])

        guard let endpointURL = URL(string: baseURL)?.appendingPathComponent("v1/chat/completions") else {
            throw AppError.localRewriteFailed("Invalid LLM base URL: \(baseURL)")
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = payloadData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (responseData, statusCode) = try performRequest(request, timeout: 30)

        if !(200...299).contains(statusCode) {
            let errorText = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if statusCode == 0 || errorText.contains("connect") || errorText.contains("Connection refused") {
                throw AppError.localRewriteFailed("Cannot connect to LLM server. Please start LLM server first.")
            }
            if errorText.contains("not found") || errorText.contains("no such model") {
                throw AppError.localRewriteFailed("Model \(model) not found. Please download the model first.")
            }
            throw AppError.localRewriteFailed("HTTP \(statusCode): \(errorText)")
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let firstChoice = choices.first,
            let message = firstChoice["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            let raw = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw AppError.localRewriteFailed("Unexpected response: \(raw)")
        }

        // Strip <think>...</think> tags if present
        var rewritten = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let thinkRange = rewritten.range(of: "<think>[\\s\\S]*?</think>\\s*", options: .regularExpression) {
            rewritten = rewritten.replacingCharacters(in: thinkRange, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if rewritten.isEmpty {
            throw AppError.localRewriteFailed("LLM server returned empty response")
        }

        return LocalRewriteResult(text: rewritten, model: model)
    }

    private static func performRequest(_ request: URLRequest, timeout: TimeInterval) throws -> (Data, Int) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseCode: Int?
        var responseError: Error?

        let task = session.dataTask(with: request) { data, response, error in
            responseData = data
            responseCode = (response as? HTTPURLResponse)?.statusCode
            responseError = error
            semaphore.signal()
        }
        task.resume()

        let waitResult = semaphore.wait(timeout: .now() + timeout + 1)
        session.invalidateAndCancel()

        if waitResult == .timedOut {
            task.cancel()
            throw AppError.localRewriteFailed("Request timed out after \(Int(timeout))s")
        }

        if let responseError {
            let desc = responseError.localizedDescription
            if desc.contains("Could not connect") || desc.contains("Connection refused") {
                throw AppError.localRewriteFailed("Cannot connect to LLM server at \(request.url?.host ?? "localhost"). Please start LLM server first.")
            }
            throw AppError.localRewriteFailed(desc)
        }

        guard let responseCode else {
            throw AppError.localRewriteFailed("No HTTP response from LLM server")
        }

        return (responseData ?? Data(), responseCode)
    }
}
```

**Step 2: Build to verify it compiles**

Run: `cd apps/mac-client && swift build 2>&1 | tail -20`
Expected: Still errors in AppController and MenuBarApp (missing switch cases) — that's OK.

**Step 3: Commit**

```
feat(local-rewrite): add LocalRewriter with OpenAI-compatible LLM API integration
```

---

### Task 5: Route `localRewrite` in AppController.commitTranscript()

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/AppController.swift:587-601`

**Step 1: Add localRewrite routing after the clarify block**

The existing code at line 587-601:

```swift
if commandParsed.effectiveMode == .clarify {
    do {
        let textToRewrite = finalText
        let localeToRewrite = localeIdentifier
        let rewritten = try await Task.detached(priority: .userInitiated) {
            try ClarifyRewriter.rewrite(
                text: textToRewrite,
                localeIdentifier: localeToRewrite
            )
        }.value
        finalText = rewritten.text
        emit("[clarify] llm rewrite applied provider=\(rewritten.provider) model=\(rewritten.model)")
    } catch {
        emit("[clarify] llm rewrite unavailable, fallback to rules: \(error)")
    }
}
```

Add after this block (after line 602's closing `}`):

```swift
if commandParsed.effectiveMode == .localRewrite {
    do {
        let textToRewrite = finalText
        let localeToRewrite = localeIdentifier
        let rewritten = try await Task.detached(priority: .userInitiated) {
            try LocalRewriter.rewrite(
                text: textToRewrite,
                localeIdentifier: localeToRewrite
            )
        }.value
        finalText = rewritten.text
        emit("[local-rewrite] llm rewrite applied model=\(rewritten.model)")
    } catch {
        emit("[local-rewrite] llm rewrite unavailable, fallback to rules: \(error)")
    }
}
```

**Step 2: Handle `localRewrite` in `normalizeDefaultMode()` (line ~859)**

Check if there's a `normalizeDefaultMode` that needs updating. Based on the grep result at line 859:

```swift
private static func normalizeDefaultMode(_ mode: OutputMode) -> OutputMode {
```

Read and ensure `localRewrite` is handled. If it maps `.raw` to `.formatOnly`, `localRewrite` should pass through unchanged (same as `clarify`).

**Step 3: Build to verify AppController compiles**

Run: `cd apps/mac-client && swift build 2>&1 | tail -20`
Expected: Only MenuBarApp errors remain.

**Step 4: Commit**

```
feat(local-rewrite): route localRewrite mode in AppController.commitTranscript
```

---

### Task 6: Add UI menu item in MenuBarApp

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/MenuBarApp.swift`

**Step 1: Add the menu item property (after clarifyModeItem, ~line 48)**

```swift
private lazy var localRewriteModeItem = NSMenuItem(
    title: "Local Rewrite (LM Studio)",
    action: #selector(setLocalRewriteMode),
    keyEquivalent: ""
)
```

**Step 2: Set target and add to submenu (around lines 337-343)**

After `clarifyModeItem.target = self`:

```swift
localRewriteModeItem.target = self
```

After `modeSubmenu.addItem(clarifyModeItem)`:

```swift
modeSubmenu.addItem(localRewriteModeItem)
```

**Step 3: Add refreshModeChecks update (around line 591-593)**

After `clarifyModeItem.state = ...`:

```swift
localRewriteModeItem.state = controller.currentMode == .localRewrite ? .on : .off
```

**Step 4: Add the action method (after setClarifyMode, ~line 741)**

```swift
@objc
private func setLocalRewriteMode() {
    controller.setMode(.localRewrite)
    preferences.saveMode(.localRewrite)
    refreshModeChecks()
}
```

**Step 5: Full build**

Run: `cd apps/mac-client && swift build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```
feat(local-rewrite): add Local Rewrite (LM Studio) menu item
```

---

### Task 7: Handle any remaining switch exhaustiveness

**Files:**
- Search all `.swift` files for `switch.*mode` or `OutputMode` patterns

**Step 1: Search for unhandled switches**

Run: `cd apps/mac-client && swift build 2>&1 | grep -i "not handled\|exhaustive\|missing case"`

If any files still have unhandled switch cases for `OutputMode`, add `localRewrite` handling. Common pattern: treat it the same as `clarify` since both use LLM rewriting.

**Step 2: Fix any remaining issues and rebuild**

Run: `cd apps/mac-client && swift build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED with zero warnings about exhaustive switches.

**Step 3: Commit (if changes needed)**

```
fix(local-rewrite): handle localRewrite in remaining switch statements
```

---

### Task 8: Manual integration test

**Step 1: Start LM Studio and load model**

Ensure LM Studio is running with `qwen/qwen3-vl-8b` loaded.

**Step 2: Run the app**

```bash
cd apps/mac-client && swift build && .build/debug/VerbatimFlow --mode local-rewrite --engine mlx-whisper
```

**Step 3: Test flow**

1. Open a text editor (TextEdit)
2. Hold the hotkey, speak a sentence in Chinese
3. Release — verify text is transcribed by MLX Whisper, then rewritten by LLM
4. Check logs for `[local-rewrite] llm rewrite applied model=qwen/qwen3-vl-8b`

**Step 4: Test error scenarios**

1. Stop LLM server → verify log shows "Cannot connect to LLM server" and text falls back to rule-based output
2. Set wrong model `VERBATIMFLOW_LLM_MODEL=nonexistent` → verify "not found" error

**Step 5: Commit all together if any tweaks**

```
test(local-rewrite): verify integration with LM Studio and MLX Whisper
```
