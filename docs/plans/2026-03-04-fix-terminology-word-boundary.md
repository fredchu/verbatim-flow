# Fix Terminology Word Boundary + Add New ASR Variants

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix Swift TerminologyDictionary word boundary to work at Chinese-English boundaries, and add new ASR misrecognition variants.

**Architecture:** The Swift `TerminologyDictionary.parseReplacement()` uses `\p{L}` (Unicode letters) for word boundaries, which treats Chinese characters as word boundaries and prevents matching patterns like `的Quint 38B在`. Change to ASCII-only boundaries (`[a-zA-Z0-9_]`) to match Python `re.ASCII` + `\b` behavior. Also add new ASR variants to both Python `terminology.py` and `terminology.txt`.

**Tech Stack:** Swift (XCTest), Python (pytest)

---

### Task 1: TDD — Fix TerminologyDictionary word boundary (Swift)

**Files:**
- Create: `apps/mac-client/Tests/VerbatimFlowTests/TerminologyDictionaryTests.swift`
- Modify: `apps/mac-client/Sources/VerbatimFlow/TerminologyDictionary.swift:127-128`

**Note:** `TerminologyDictionary` exists only on `dev` branch. Since we're on `feat/breeze-asr`, first copy the file from `dev`:

```bash
git show dev:apps/mac-client/Sources/VerbatimFlow/TerminologyDictionary.swift > apps/mac-client/Sources/VerbatimFlow/TerminologyDictionary.swift
```

Also copy `DictationVocabulary.swift` (needed to compile, referenced in AppController):

```bash
git show dev:apps/mac-client/Sources/VerbatimFlow/DictationVocabulary.swift > apps/mac-client/Sources/VerbatimFlow/DictationVocabulary.swift
```

**Step 1: Write failing test**

Create `apps/mac-client/Tests/VerbatimFlowTests/TerminologyDictionaryTests.swift`:

```swift
import XCTest
@testable import VerbatimFlow

final class TerminologyDictionaryTests: XCTestCase {

    // Helper: build a single replacement rule and apply it
    private func applyRule(source: String, target: String, to text: String) -> String {
        let rules = [TerminologyRules.Replacement(source: source, target: target,
            regex: TerminologyDictionaryTests.buildRegex(source: source)!)]
        return TerminologyDictionary.applyReplacements(to: text, replacements: rules).text
    }

    private static func buildRegex(source: String) -> NSRegularExpression? {
        let escaped = NSRegularExpression.escapedPattern(for: source)
        let hasAlphanumeric = source.rangeOfCharacter(from: CharacterSet.alphanumerics) != nil
        let pattern = hasAlphanumeric
            ? "(?<![a-zA-Z0-9_])\(escaped)(?![a-zA-Z0-9_])"
            : escaped
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    // --- Chinese-English boundary tests ---

    func testChineseBeforeEnglishTerm() {
        // 的Quint should match (的 is Chinese, not ASCII)
        let result = applyRule(source: "Quint 38B", target: "Qwen3 8B",
            to: "Orama的Quint 38B在做校正")
        XCTAssertEqual(result, "Orama的Qwen3 8B在做校正")
    }

    func testChineseAfterEnglishTerm() {
        let result = applyRule(source: "LMS Studio", target: "LM Studio",
            to: "用LMS Studio跑模型")
        XCTAssertEqual(result, "用LM Studio跑模型")
    }

    func testPureEnglishBoundary() {
        let result = applyRule(source: "Quint 3", target: "Qwen3",
            to: "use Quint 3 model")
        XCTAssertEqual(result, "use Qwen3 model")
    }

    func testEnglishBoundaryPreventsPartialMatch() {
        // preQuint should NOT match (leading ASCII alpha)
        let result = applyRule(source: "Quint", target: "Qwen",
            to: "preQuint model")
        XCTAssertEqual(result, "preQuint model")
    }

    func testChineseOnlyRule() {
        // Chinese rules have no word boundary
        let result = applyRule(source: "歐拉瑪", target: "Ollama",
            to: "用歐拉瑪跑模型")
        XCTAssertEqual(result, "用Ollama跑模型")
    }
}
```

**Step 2: Run test to verify it fails**

```bash
cd /Users/fredchu/dev/verbatim-flow/apps/mac-client && swift test --filter TerminologyDictionaryTests 2>&1 | tail -20
```

Expected: Compilation error (TerminologyDictionary.swift not on this branch yet) or test failure (old `\p{L}` boundary).

**Step 3: Copy TerminologyDictionary.swift from dev and fix**

```bash
git show dev:apps/mac-client/Sources/VerbatimFlow/TerminologyDictionary.swift > apps/mac-client/Sources/VerbatimFlow/TerminologyDictionary.swift
git show dev:apps/mac-client/Sources/VerbatimFlow/DictationVocabulary.swift > apps/mac-client/Sources/VerbatimFlow/DictationVocabulary.swift
```

Then in `TerminologyDictionary.swift`, change line 128:

```swift
// OLD:
        let pattern = needsWordBoundary
            ? "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])"
            : escaped

// NEW:
        let pattern = needsWordBoundary
            ? "(?<![a-zA-Z0-9_])\(escaped)(?![a-zA-Z0-9_])"
            : escaped
```

**Step 4: Run test to verify it passes**

```bash
cd /Users/fredchu/dev/verbatim-flow/apps/mac-client && swift test --filter TerminologyDictionaryTests 2>&1 | tail -20
```

Expected: 5 tests PASS

**Step 5: Commit**

```bash
git add apps/mac-client/Sources/VerbatimFlow/TerminologyDictionary.swift \
       apps/mac-client/Sources/VerbatimFlow/DictationVocabulary.swift \
       apps/mac-client/Tests/VerbatimFlowTests/TerminologyDictionaryTests.swift
git commit -m "fix: use ASCII-only word boundary in TerminologyDictionary

Unicode \\p{L} boundary treated Chinese characters as word boundaries,
preventing matches at Chinese-English boundaries (e.g. 的Quint 38B在).
Changed to [a-zA-Z0-9_] to match Python re.ASCII + \\b behavior."
```

---

### Task 2: Add new ASR variants to terminology rules

**Files:**
- Modify: `apps/mac-client/python/scripts/terminology.py`
- Modify: `apps/mac-client/python/tests/test_terminology.py`
- Modify: `~/Library/Application Support/VerbatimFlow/terminology.txt`

**Step 1: Add rules to Python terminology.py**

Add these new rules to the English section:

```python
(r'\bOrama\b', 'Ollama', re.IGNORECASE | re.ASCII),
(r'\bAlarm\s+Studio\b', 'LM Studio', re.IGNORECASE | re.ASCII),
```

Update test count and add tests:

```python
def test_orama(self):
    assert apply_terminology_regex("用Orama跑模型") == "用Ollama跑模型"

def test_alarm_studio(self):
    assert apply_terminology_regex("用Alarm Studio搭配") == "用LM Studio搭配"
```

**Step 2: Add rules to terminology.txt**

Add to `~/Library/Application Support/VerbatimFlow/terminology.txt`:

```
Orama => Ollama
Alarm Studio => LM Studio
```

**Step 3: Run Python tests**

```bash
cd /Users/fredchu/dev/verbatim-flow/apps/mac-client/python && .venv/bin/python -m pytest tests/test_terminology.py -v
```

Expected: All tests PASS

**Step 4: Commit**

```bash
git add apps/mac-client/python/scripts/terminology.py \
       apps/mac-client/python/tests/test_terminology.py
git commit -m "feat: add Orama and Alarm Studio ASR misrecognition rules

Orama → Ollama, Alarm Studio → LM Studio"
```

---

### Task 3: Merge into dev and rebuild

**Step 1: Merge**

```bash
git checkout dev
git merge feat/breeze-asr --no-edit
```

**Step 2: Resolve conflicts if any**

The TerminologyDictionary.swift word boundary fix should apply cleanly since we copied the file from dev and only changed one line.

**Step 3: Build and install**

```bash
./scripts/build-native-app.sh
cp -R apps/mac-client/dist/VerbatimFlow.app /Applications/VerbatimFlow.app
```

**Step 4: Switch back**

```bash
git checkout feat/breeze-asr
```
