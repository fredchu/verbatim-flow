import AppKit
import Foundation

final class HotkeyMonitor {
    private let hotkey: Hotkey
    private let onPressed: () -> Void
    private let onReleased: () -> Void

    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var isPressed = false

    init(hotkey: Hotkey, onPressed: @escaping () -> Void, onReleased: @escaping () -> Void) {
        self.hotkey = hotkey
        self.onPressed = onPressed
        self.onReleased = onReleased
    }

    func start() {
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
        }

        keyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp]) { [weak self] event in
            self?.handleKeyUp(event)
        }
    }

    deinit {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        if let keyUpMonitor {
            NSEvent.removeMonitor(keyUpMonitor)
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard event.keyCode == hotkey.keyCode else {
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isSuperset(of: hotkey.modifiers) else {
            return
        }

        guard !isPressed else {
            return
        }
        isPressed = true
        onPressed()
    }

    private func handleKeyUp(_ event: NSEvent) {
        guard event.keyCode == hotkey.keyCode else {
            return
        }

        guard isPressed else {
            return
        }
        isPressed = false
        onReleased()
    }
}
