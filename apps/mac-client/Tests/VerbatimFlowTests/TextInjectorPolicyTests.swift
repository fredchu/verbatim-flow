import XCTest
@testable import VerbatimFlow

final class TextInjectorPolicyTests: XCTestCase {
    func testCodexBundleUsesPasteFallback() {
        XCTAssertTrue(TextInjector.shouldPreferPasteFallback(for: "com.openai.codex"))
    }

    func testCodexSubBundleUsesPasteFallback() {
        XCTAssertTrue(TextInjector.shouldPreferPasteFallback(for: "com.openai.codex.preview"))
    }

    func testRegularBundleDoesNotUsePasteFallback() {
        XCTAssertFalse(TextInjector.shouldPreferPasteFallback(for: "com.apple.TextEdit"))
    }
}
