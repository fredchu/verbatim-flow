# Fix Duplicate Punctuation in LLM Rewrite Modes

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate duplicate/consecutive punctuation (`，，` `。。` `，。`) in local rewrite and clarify modes.

**Architecture:** Two-part fix: (A) Skip sherpa-onnx punctuation for LLM rewrite modes since LLM adds its own punctuation; (B) Add defensive regex cleanup to collapse any consecutive punctuation before text injection. Both changes are in `AppController.commitTranscript()` on the `feat/breeze-asr` branch.

**Tech Stack:** Swift, regex

---

### Root Cause

`feat/breeze-asr` added `PunctuationPostProcessor` (sherpa-onnx) before TextGuard. `feat/local-rewrite` added `LocalRewriter` (LLM) after TextGuard. When merged in `dev`, text gets punctuated twice: once by sherpa-onnx, once by LLM. Same issue affects `clarify` mode (ClarifyRewriter).

### Task 1: Skip PunctuationPostProcessor for LLM rewrite modes

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/AppController.swift:577-588`

**Step 1: Modify PunctuationPostProcessor guard**

Current code (line 577-588):
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
```

Change to:
```swift
// --- Punctuation + terminology post-processing (Python) ---
// Skip for LLM rewrite modes: LLM adds its own punctuation
let needsPunctuation = commandParsed.effectiveMode != .clarify
    && commandParsed.effectiveMode != .localRewrite
let postprocessedContent: String
if needsPunctuation {
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
} else {
    postprocessedContent = commandParsed.content
    emit("[punctuation] skipped for \(commandParsed.effectiveMode.rawValue) mode (LLM handles punctuation)")
}
```

**Step 2: Build to verify compilation**

Run: `cd apps/mac-client && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 3: Commit**

```bash
git add apps/mac-client/Sources/VerbatimFlow/AppController.swift
git commit -m "fix: skip sherpa-onnx punctuation for LLM rewrite modes

LLM (clarify/localRewrite) adds its own punctuation. Running
sherpa-onnx first caused duplicate punctuation marks (，， 。。 ，。)."
```

---

### Task 2: Add defensive duplicate punctuation cleanup

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/AppController.swift` (before `onTranscriptCommitted`)

**Step 1: Add cleanup before injection**

After the localRewrite block (after line ~656 in full-build) and before `onTranscriptCommitted?(finalText)`, add:

```swift
// Defensive: collapse consecutive duplicate punctuation (e.g. ，， → ，)
finalText = finalText.replacingOccurrences(
    of: "([，。！？；：、,\\.!?;:]){2,}",
    with: "$1",
    options: .regularExpression
)
```

This regex matches 2+ consecutive identical punctuation characters and collapses them to one.

**Step 2: Build to verify compilation**

Run: `cd apps/mac-client && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 3: Commit**

```bash
git add apps/mac-client/Sources/VerbatimFlow/AppController.swift
git commit -m "fix: add defensive cleanup for consecutive duplicate punctuation

Collapses ，， → ， and similar patterns as safety net for all modes."
```

---

### Task 3: Merge fix into dev and rebuild

**Step 1: Merge feat/breeze-asr into dev**

```bash
git checkout dev
git merge feat/breeze-asr
```

**Step 2: Resolve any conflicts in AppController.swift**

The merge should apply cleanly since changes are in the same area that already exists in both branches.

**Step 3: Build and install**

```bash
./scripts/build-native-app.sh
```

**Step 4: Commit merge if needed, verify app launches**
