# LLM Model Switcher Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a settings window to switch LLM model ID and system prompt for punctuation and Local Rewrite, and migrate LocalRewriter from Ollama to LM Studio.

**Architecture:** 5 new UserDefaults keys store base URL, model IDs, and prompts. A new `LLMSettingsWindow.swift` provides the editing UI. `LocalRewriter.swift` is rewritten from Ollama `/api/chat` to OpenAI-compatible `/v1/chat/completions`. Python `_add_punctuation()` reads an optional prompt env var.

**Tech Stack:** Swift 5.9 (AppKit: NSWindow, NSTextField, NSTextView, NSScrollView), Python (os.environ), UserDefaults

**Design doc:** `docs/plans/2026-03-03-llm-model-switcher-design.md`

---

### Task 1: AppPreferences — add 5 LLM settings keys

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/AppPreferences.swift`

**Step 1: Add keys and load/save/clear methods**

Add inside `Key` enum:

```swift
static let llmBaseURL = "verbatimflow.llmBaseURL"
static let punctuationModel = "verbatimflow.punctuationModel"
static let punctuationPrompt = "verbatimflow.punctuationPrompt"
static let localRewriteModel = "verbatimflow.localRewriteModel"
static let localRewritePrompt = "verbatimflow.localRewritePrompt"
```

Add methods (all String?, not enum-based):

```swift
// MARK: - LLM Settings

func loadLLMBaseURL() -> String? {
    defaults.string(forKey: Key.llmBaseURL)
}

func saveLLMBaseURL(_ value: String) {
    defaults.set(value, forKey: Key.llmBaseURL)
}

func loadPunctuationModel() -> String? {
    defaults.string(forKey: Key.punctuationModel)
}

func savePunctuationModel(_ value: String) {
    defaults.set(value, forKey: Key.punctuationModel)
}

func loadPunctuationPrompt() -> String? {
    defaults.string(forKey: Key.punctuationPrompt)
}

func savePunctuationPrompt(_ value: String) {
    defaults.set(value, forKey: Key.punctuationPrompt)
}

func loadLocalRewriteModel() -> String? {
    defaults.string(forKey: Key.localRewriteModel)
}

func saveLocalRewriteModel(_ value: String) {
    defaults.set(value, forKey: Key.localRewriteModel)
}

func loadLocalRewritePrompt() -> String? {
    defaults.string(forKey: Key.localRewritePrompt)
}

func saveLocalRewritePrompt(_ value: String) {
    defaults.set(value, forKey: Key.localRewritePrompt)
}

func clearLLMSettings() {
    for key in [Key.llmBaseURL, Key.punctuationModel, Key.punctuationPrompt,
                Key.localRewriteModel, Key.localRewritePrompt] {
        defaults.removeObject(forKey: key)
    }
}
```

**Step 2: Build to verify compilation**

Run: `cd apps/mac-client && swift build 2>&1 | tail -5`
Expected: Build succeeded

**Step 3: Commit**

```
feat: add LLM settings keys to AppPreferences
```

---

### Task 2: LLMSettingsWindow — create settings UI

**Files:**
- Create: `apps/mac-client/Sources/VerbatimFlow/LLMSettingsWindow.swift`

**Step 1: Create the window class**

```swift
import AppKit

final class LLMSettingsWindow: NSWindow {
    private let prefs = AppPreferences()

    // Defaults (must match Python and LocalRewriter hardcoded values)
    static let defaultBaseURL = "http://localhost:1234"
    static let defaultPunctuationModel = "qwen/qwen3-vl-8b"
    static let defaultPunctuationPrompt = """
        你是標點符號專家。請為以下中文語音辨識文字加上適當的全形標點符號\
        （，。、？！：；「」『』《》）。只加標點，不改動任何文字內容。\
        直接輸出結果，不要解釋。/no_think
        """
    static let defaultRewriteModel = "qwen/qwen3-vl-8b"
    static let defaultRewritePrompt = """
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

    private let baseURLField = NSTextField()
    private let punctuationModelField = NSTextField()
    private let punctuationPromptView = NSTextView()
    private let rewriteModelField = NSTextField()
    private let rewritePromptView = NSTextView()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "LLM Settings"
        isReleasedWhenClosed = false
        center()
        setupUI()
        loadValues()
    }

    private func setupUI() {
        let contentView = NSView(frame: self.contentRect(forFrameRect: frame))
        self.contentView = contentView

        var y = contentView.bounds.height - 10

        // -- General section --
        y = addSectionHeader("General", to: contentView, y: y)
        y = addLabel("LM Studio Base URL:", to: contentView, y: y)
        y = addTextField(baseURLField, placeholder: Self.defaultBaseURL, to: contentView, y: y)

        y -= 10 // spacing between sections

        // -- Punctuation section --
        y = addSectionHeader("Punctuation", to: contentView, y: y)
        y = addLabel("Model ID:", to: contentView, y: y)
        y = addTextField(punctuationModelField, placeholder: Self.defaultPunctuationModel, to: contentView, y: y)
        y = addLabel("System Prompt:", to: contentView, y: y)
        y = addTextView(punctuationPromptView, to: contentView, y: y)

        y -= 10

        // -- Local Rewrite section --
        y = addSectionHeader("Local Rewrite", to: contentView, y: y)
        y = addLabel("Model ID:", to: contentView, y: y)
        y = addTextField(rewriteModelField, placeholder: Self.defaultRewriteModel, to: contentView, y: y)
        y = addLabel("System Prompt:", to: contentView, y: y)
        y = addTextView(rewritePromptView, to: contentView, y: y)

        y -= 10

        // -- Buttons --
        let resetButton = NSButton(title: "Reset Defaults", target: self, action: #selector(resetDefaults))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveButton.keyEquivalent = "\r" // Enter key

        let buttonY = max(y - 30, 10)
        resetButton.frame = NSRect(x: 250, y: buttonY, width: 120, height: 30)
        saveButton.frame = NSRect(x: 380, y: buttonY, width: 100, height: 30)
        contentView.addSubview(resetButton)
        contentView.addSubview(saveButton)
    }

    // MARK: - UI helpers

    private func addSectionHeader(_ title: String, to view: NSView, y: CGFloat) -> CGFloat {
        let label = NSTextField(labelWithString: "── \(title) ──")
        label.font = NSFont.boldSystemFont(ofSize: 13)
        label.frame = NSRect(x: 20, y: y - 20, width: 460, height: 20)
        view.addSubview(label)
        return y - 28
    }

    private func addLabel(_ text: String, to view: NSView, y: CGFloat) -> CGFloat {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.frame = NSRect(x: 20, y: y - 18, width: 460, height: 18)
        view.addSubview(label)
        return y - 22
    }

    private func addTextField(_ field: NSTextField, placeholder: String, to view: NSView, y: CGFloat) -> CGFloat {
        field.placeholderString = placeholder
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        field.frame = NSRect(x: 20, y: y - 24, width: 460, height: 24)
        view.addSubview(field)
        return y - 30
    }

    private func addTextView(_ textView: NSTextView, to view: NSView, y: CGFloat) -> CGFloat {
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: y - 90, width: 460, height: 90))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        textView.minSize = NSSize(width: 0, height: 90)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        scrollView.documentView = textView
        view.addSubview(scrollView)
        return y - 96
    }

    // MARK: - Load / Save / Reset

    private func loadValues() {
        baseURLField.stringValue = prefs.loadLLMBaseURL() ?? Self.defaultBaseURL
        punctuationModelField.stringValue = prefs.loadPunctuationModel() ?? Self.defaultPunctuationModel
        punctuationPromptView.string = prefs.loadPunctuationPrompt() ?? Self.defaultPunctuationPrompt
        rewriteModelField.stringValue = prefs.loadLocalRewriteModel() ?? Self.defaultRewriteModel
        rewritePromptView.string = prefs.loadLocalRewritePrompt() ?? Self.defaultRewritePrompt
    }

    @objc private func saveSettings() {
        prefs.saveLLMBaseURL(baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        prefs.savePunctuationModel(punctuationModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        prefs.savePunctuationPrompt(punctuationPromptView.string.trimmingCharacters(in: .whitespacesAndNewlines))
        prefs.saveLocalRewriteModel(rewriteModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        prefs.saveLocalRewritePrompt(rewritePromptView.string.trimmingCharacters(in: .whitespacesAndNewlines))
        close()
    }

    @objc private func resetDefaults() {
        prefs.clearLLMSettings()
        loadValues()
    }
}
```

**Step 2: Build to verify compilation**

Run: `cd apps/mac-client && swift build 2>&1 | tail -5`
Expected: Build succeeded

**Step 3: Commit**

```
feat: add LLMSettingsWindow for model/prompt editing
```

---

### Task 3: MenuBarApp — add "LLM Settings..." menu item

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/MenuBarApp.swift`

**Step 1: Add window property and menu item**

Near the top of the class (around line 29, near other menu item declarations), add:

```swift
private var llmSettingsWindow: LLMSettingsWindow?
private lazy var llmSettingsItem: NSMenuItem = NSMenuItem(
    title: "LLM Settings...",
    action: #selector(openLLMSettings),
    keyEquivalent: ""
)
```

**Step 2: Add menu item to settings submenu**

In the `settingsSubmenu` assembly (around line 470, before `settingsMenuItem.submenu`), add:

```swift
settingsSubmenu.addItem(llmSettingsItem)
```

**Step 3: Add action method**

Add alongside other `@objc` action methods:

```swift
@objc private func openLLMSettings() {
    if llmSettingsWindow == nil {
        llmSettingsWindow = LLMSettingsWindow()
    }
    llmSettingsWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}
```

**Step 4: Set target on menu item**

In the method that sets targets on menu items (look for pattern `xxxItem.target = self`), add:

```swift
llmSettingsItem.target = self
```

**Step 5: Build to verify compilation**

Run: `cd apps/mac-client && swift build 2>&1 | tail -5`
Expected: Build succeeded

**Step 6: Commit**

```
feat: add LLM Settings menu item to MenuBarApp
```

---

### Task 4: LocalRewriter — migrate from Ollama to LM Studio

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/LocalRewriter.swift` (on `feat/local-rewrite` branch)

This task requires checking out `feat/local-rewrite` first since `LocalRewriter.swift` only exists on that branch.

**Step 1: Rewrite LocalRewriter.swift**

Changes needed:
1. `defaultBaseURL` → `"http://localhost:1234"`
2. `defaultModel` → `"qwen/qwen3-vl-8b"`
3. Read model/prompt/baseURL from `AppPreferences` with fallback to defaults
4. Endpoint: `{baseURL}/v1/chat/completions` (not `/api/chat`)
5. Payload format: OpenAI-compatible (`temperature` at top level, `max_tokens` instead of `options.num_predict`, remove `keep_alive`)
6. Response parsing: `choices[0].message.content` (not `message.content`)
7. Add `<think>` strip safety net
8. Update error messages from "Ollama" to "LM Studio"

Key changes to `rewrite()`:

```swift
private static let defaultBaseURL = "http://localhost:1234"
private static let defaultModel = "qwen/qwen3-vl-8b"
private static let defaultSystemPrompt = """
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
```

Read settings from UserDefaults:

```swift
let prefs = AppPreferences()
let baseURL = prefs.loadLLMBaseURL()?.isEmpty == false
    ? prefs.loadLLMBaseURL()! : defaultBaseURL
let model = prefs.loadLocalRewriteModel()?.isEmpty == false
    ? prefs.loadLocalRewriteModel()! : defaultModel
let systemPrompt = prefs.loadLocalRewritePrompt()?.isEmpty == false
    ? prefs.loadLocalRewritePrompt()! : defaultSystemPrompt
```

New payload (OpenAI format):

```swift
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
```

New endpoint:

```swift
guard let endpointURL = URL(string: baseURL)?
    .appendingPathComponent("v1/chat/completions") else {
    throw AppError.localRewriteFailed("Invalid LM Studio base URL: \(baseURL)")
}
```

New response parsing:

```swift
guard
    let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
    let choices = json["choices"] as? [[String: Any]],
    let firstChoice = choices.first,
    let message = firstChoice["message"] as? [String: Any],
    let content = message["content"] as? String
else {
    let raw = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    throw AppError.localRewriteFailed("Unexpected response: \(raw)")
}

// Strip <think> blocks (Qwen3 safety net)
var rewritten = content.trimmingCharacters(in: .whitespacesAndNewlines)
if let thinkRange = rewritten.range(of: "<think>[\\s\\S]*?</think>",
                                     options: .regularExpression) {
    rewritten = rewritten.replacingCharacters(in: thinkRange, with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
```

Update error messages: replace "Ollama" → "LM Studio", "11434" → "1234".

**Step 2: Build to verify compilation**

Run: `cd apps/mac-client && swift build 2>&1 | tail -5`
Expected: Build succeeded

**Step 3: Commit**

```
feat(local-rewrite): migrate LocalRewriter from Ollama to LM Studio
```

---

### Task 5: SpeechTranscriber — inject LLM env vars for Python

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/SpeechTranscriber.swift`

**Step 1: Inject env vars before Python subprocess**

In `transcribeMlxWhisperAudioFile()` (line ~912), after `process.environment = env`, add UserDefaults-based env injection:

```swift
// Inject LLM settings for _add_punctuation() in Python.
let llmPrefs = AppPreferences()
if let baseURL = llmPrefs.loadLLMBaseURL(), !baseURL.isEmpty {
    env["VERBATIMFLOW_LLM_BASE_URL"] = baseURL
}
if let model = llmPrefs.loadPunctuationModel(), !model.isEmpty {
    env["VERBATIMFLOW_LLM_MODEL"] = model
}
if let prompt = llmPrefs.loadPunctuationPrompt(), !prompt.isEmpty {
    env["VERBATIMFLOW_LLM_PROMPT"] = prompt
}
process.environment = env
```

Note: the existing `process.environment = env` on line 912 should be removed (or moved after the new code). The final `process.environment = env` assignment must come after all env modifications.

**Step 2: Build to verify compilation**

Run: `cd apps/mac-client && swift build 2>&1 | tail -5`
Expected: Build succeeded

**Step 3: Commit**

```
feat: inject LLM UserDefaults into Python env vars
```

---

### Task 6: Python — read prompt from env var

**Files:**
- Modify: `apps/mac-client/python/verbatim_flow/mlx_whisper_transcriber.py`
- Modify: `apps/mac-client/python/tests/test_mlx_whisper_transcriber.py`

**Step 1: Write the failing test**

Add to `test_mlx_whisper_transcriber.py`:

```python
class TestAddPunctuationCustomPrompt(unittest.TestCase):
    @patch("verbatim_flow.mlx_whisper_transcriber.urllib.request.urlopen")
    def test_custom_prompt_from_env(self, mock_urlopen):
        """VERBATIMFLOW_LLM_PROMPT env var should override the default system prompt."""
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "choices": [{"message": {"content": "自訂結果"}}]
        }).encode()
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        custom_prompt = "你是測試用的自訂提示詞。/no_think"
        with patch.dict("os.environ", {"VERBATIMFLOW_LLM_PROMPT": custom_prompt}):
            _add_punctuation("測試文字")

        call_data = json.loads(mock_urlopen.call_args[0][0].data)
        self.assertEqual(call_data["messages"][0]["content"], custom_prompt)
```

**Step 2: Run test to verify it fails**

Run: `cd apps/mac-client && python -m pytest python/tests/test_mlx_whisper_transcriber.py::TestAddPunctuationCustomPrompt -v`
Expected: FAIL (current code ignores VERBATIMFLOW_LLM_PROMPT)

**Step 3: Modify `_add_punctuation()` to read prompt env var**

In `mlx_whisper_transcriber.py`, around line 97, after reading `model`:

```python
default_prompt = (
    "你是標點符號專家。請為以下中文語音辨識文字加上適當的全形標點符號"
    "（，。、？！：；「」『』《》）。只加標點，不改動任何文字內容。"
    "直接輸出結果，不要解釋。/no_think"
)
prompt = os.environ.get("VERBATIMFLOW_LLM_PROMPT", default_prompt)
```

Then change the messages payload to use `prompt` variable:

```python
"messages": [
    {
        "role": "system",
        "content": prompt,
    },
    {"role": "user", "content": text},
],
```

**Step 4: Run test to verify it passes**

Run: `cd apps/mac-client && python -m pytest python/tests/test_mlx_whisper_transcriber.py::TestAddPunctuationCustomPrompt -v`
Expected: PASS

**Step 5: Run all punctuation tests**

Run: `cd apps/mac-client && python -m pytest python/tests/test_mlx_whisper_transcriber.py -v`
Expected: All pass (except pre-existing opencc test)

**Step 6: Commit**

```
feat(breeze-asr): support custom punctuation prompt via env var
```

---

### Task 7: Build & Smoke Test

**Step 1: Merge all branches into tmp build branch**

```bash
git checkout main
git checkout -b tmp/full-build-$(date +%Y%m%d-%H%M%S)
git merge feat/breeze-asr --no-edit
git merge feat/local-rewrite --no-edit  # resolve CLIConfig conflict if needed
git merge feat/mlx-whisper --no-edit
git merge fix/hotkey-carbon-event-handling --no-edit
git merge fix/mlx-whisper-cjk-punctuation --no-edit
```

**Step 2: Build and install**

```bash
./scripts/build-native-app.sh
pkill -f VerbatimFlow || true
rm -rf /Applications/VerbatimFlow.app
cp -R apps/mac-client/dist/VerbatimFlow.app /Applications/
open /Applications/VerbatimFlow.app
```

**Step 3: Manual smoke test**

1. Open menu → Settings → LLM Settings...
2. Verify 5 fields are populated with defaults
3. Change punctuation model, click Save
4. Record something → verify punctuation uses new model
5. Reset Defaults → verify fields restore
6. Test Local Rewrite mode with LM Studio

**Step 4: Cleanup**

```bash
git checkout feat/breeze-asr  # or feat/local-rewrite
git branch -D tmp/full-build-*
```
