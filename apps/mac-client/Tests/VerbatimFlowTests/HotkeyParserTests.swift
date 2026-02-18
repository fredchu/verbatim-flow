import XCTest
@testable import VerbatimFlow

final class HotkeyParserTests: XCTestCase {
    func testModifierOnlyParses() throws {
        let hotkey = try HotkeyParser.parse(combo: "shift+option")
        XCTAssertNil(hotkey.keyCode)
        XCTAssertTrue(hotkey.modifiers.contains(.shift))
        XCTAssertTrue(hotkey.modifiers.contains(.option))
    }

    func testOptionAliasParses() throws {
        let hotkey = try HotkeyParser.parse(combo: "shift+option+space")
        XCTAssertEqual(hotkey.keyCode, UInt16(49))
        XCTAssertTrue(hotkey.modifiers.contains(.shift))
        XCTAssertTrue(hotkey.modifiers.contains(.option))
    }

    func testAltAliasParses() throws {
        let hotkey = try HotkeyParser.parse(combo: "shift+alt+space")
        XCTAssertEqual(hotkey.keyCode, UInt16(49))
        XCTAssertTrue(hotkey.modifiers.contains(.shift))
        XCTAssertTrue(hotkey.modifiers.contains(.option))
    }
}
