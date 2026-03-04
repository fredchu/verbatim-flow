import XCTest
@testable import VerbatimFlow

final class TerminologyDictionaryTests: XCTestCase {

    private func makeReplacement(source: String, target: String) -> TerminologyRules.Replacement? {
        let escaped = NSRegularExpression.escapedPattern(for: source)
        let hasAlpha = source.rangeOfCharacter(from: CharacterSet.alphanumerics) != nil
        // Use ASCII-only boundaries — the FIXED pattern
        let pattern = hasAlpha
            ? "(?<![a-zA-Z0-9_])\(escaped)(?![a-zA-Z0-9_])"
            : escaped
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        return TerminologyRules.Replacement(source: source, target: target, regex: regex)
    }

    private func apply(source: String, target: String, to text: String) -> String {
        guard let rule = makeReplacement(source: source, target: target) else {
            return text
        }
        return TerminologyDictionary.applyReplacements(to: text, replacements: [rule]).text
    }

    func testChineseBeforeEnglishTerm() {
        let result = apply(source: "Quint 38B", target: "Qwen3 8B",
            to: "Orama的Quint 38B在做校正")
        XCTAssertEqual(result, "Orama的Qwen3 8B在做校正")
    }

    func testChineseAfterEnglishTerm() {
        let result = apply(source: "LMS Studio", target: "LM Studio",
            to: "用LMS Studio跑模型")
        XCTAssertEqual(result, "用LM Studio跑模型")
    }

    func testPureEnglishBoundary() {
        let result = apply(source: "Quint 3", target: "Qwen3",
            to: "use Quint 3 model")
        XCTAssertEqual(result, "use Qwen3 model")
    }

    func testEnglishBoundaryPreventsPartialMatch() {
        let result = apply(source: "Quint", target: "Qwen",
            to: "preQuint model")
        XCTAssertEqual(result, "preQuint model")
    }

    func testChineseOnlyRule() {
        let result = apply(source: "歐拉瑪", target: "Ollama",
            to: "用歐拉瑪跑模型")
        XCTAssertEqual(result, "用Ollama跑模型")
    }
}
