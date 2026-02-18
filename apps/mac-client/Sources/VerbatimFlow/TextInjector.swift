import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class TextInjector {
    func promptAccessibilityIfNeeded() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func insert(text: String) throws {
        guard !text.isEmpty else {
            return
        }

        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try postCommandV()

        // Restore previous clipboard text shortly after paste to reduce clipboard side effects.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }
    }

    private func postCommandV() throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw AppError.eventSourceCreationFailed
        }

        let vKeyCode: CGKeyCode = 9 // key 'v' in ANSI layout
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else {
            throw AppError.eventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
