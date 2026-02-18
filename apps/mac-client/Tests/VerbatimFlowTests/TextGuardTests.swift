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
}
