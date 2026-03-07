import XCTest
@testable import VerbatimFlow

final class TextGuardTests: XCTestCase {
    func testRawModeReturnsOriginal() {
        let guardEngine = TextGuard(mode: .raw)
        let result = guardEngine.apply(raw: "  hello   world  ")
        XCTAssertEqual(result.text, "hello   world")
        XCTAssertFalse(result.fellBackToRaw)
    }

    func testFormatOnlyKeepsSemantics() {
        let guardEngine = TextGuard(mode: .formatOnly)
        let result = guardEngine.apply(raw: "Hello ,world !")
        XCTAssertEqual(result.text, "Hello, world!")
        XCTAssertFalse(result.fellBackToRaw)
    }

    func testFormatOnlyUsesFullWidthChinesePunctuation() {
        let guardEngine = TextGuard(mode: .formatOnly)
        let result = guardEngine.apply(raw: "你好, 世界! 这个叫 commit.")
        XCTAssertEqual(result.text, "你好，世界！这个叫 commit。")
        XCTAssertFalse(result.fellBackToRaw)
    }

    func testFormatOnlyKeepsAsciiPunctuationInsideURLs() {
        let guardEngine = TextGuard(mode: .formatOnly)
        let result = guardEngine.apply(raw: "访问 https://axtonliu.ai/test, 谢谢.")
        XCTAssertEqual(result.text, "访问 https://axtonliu.ai/test，谢谢。")
        XCTAssertFalse(result.fellBackToRaw)
    }

    func testFormatOnlyAddsLightweightChinesePunctuationWhenMissing() {
        let guardEngine = TextGuard(mode: .formatOnly)
        let result = guardEngine.apply(raw: "你看现在这个头的标点又没有了")
        XCTAssertEqual(result.text, "你看，现在这个头的标点又没有了。")
        XCTAssertFalse(result.fellBackToRaw)
    }

    func testFormatOnlyDoesNotForcePeriodOnShortChineseFragment() {
        let guardEngine = TextGuard(mode: .formatOnly)
        let result = guardEngine.apply(raw: "计划今天要发的")
        XCTAssertEqual(result.text, "计划今天要发的")
        XCTAssertFalse(result.fellBackToRaw)
    }
}
