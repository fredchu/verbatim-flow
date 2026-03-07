import XCTest
@testable import VerbatimFlow

final class MixedLanguageEnhancerTests: XCTestCase {
    func testApplyJoinsSplitTechnicalTerms() {
        let result = MixedLanguageEnhancer.apply(
            text: "这个功能会发到 open ai 和 you tube 上",
            localeIdentifier: "zh-CN",
            vocabularyHints: ["OpenAI", "YouTube"]
        )

        XCTAssertEqual(result.text, "这个功能会发到 OpenAI 和 YouTube 上")
        XCTAssertEqual(result.appliedRules, ["open ai -> OpenAI", "you tube -> YouTube"])
    }

    func testApplyJoinsHyphenatedAndNumericTerms() {
        let result = MixedLanguageEnhancer.apply(
            text: "我想测试 b roll 和 gpt 5 还有 i term 2",
            localeIdentifier: "zh-CN",
            vocabularyHints: ["B-roll", "GPT-5", "iTerm2"]
        )

        XCTAssertEqual(result.text, "我想测试 B-roll 和 GPT-5 还有 iTerm2")
        XCTAssertEqual(result.appliedRules, ["b roll -> B-roll", "gpt 5 -> GPT-5", "i term 2 -> iTerm2"])
    }

    func testContextualTermDoesNotOverCorrectWithoutContext() {
        let result = MixedLanguageEnhancer.apply(
            text: "这个 ta na 说的其实没错",
            localeIdentifier: "zh-CN",
            vocabularyHints: ["Tana"]
        )

        XCTAssertEqual(result.text, "这个 ta na 说的其实没错")
        XCTAssertEqual(result.appliedRules, [])
    }

    func testContextualTermCorrectsWhenKnowledgeContextExists() {
        let result = MixedLanguageEnhancer.apply(
            text: "我把 ta na 里的笔记同步过来了",
            localeIdentifier: "zh-CN",
            vocabularyHints: ["Tana"]
        )

        XCTAssertEqual(result.text, "我把 Tana 里的笔记同步过来了")
        XCTAssertEqual(result.appliedRules, ["ta na -> Tana"])
    }
}
