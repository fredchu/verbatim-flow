import AppKit
import Foundation

@MainActor
final class AppController {
    private let config: CLIConfig
    private let transcriber: SpeechTranscriber
    private let textGuard: TextGuard
    private let injector = TextInjector()
    private var hotkeyMonitor: HotkeyMonitor?
    private var isRecording = false

    init(config: CLIConfig) {
        self.config = config
        self.transcriber = SpeechTranscriber(
            localeIdentifier: config.localeIdentifier,
            requireOnDeviceRecognition: config.requireOnDeviceRecognition
        )
        self.textGuard = TextGuard(mode: config.mode)
    }

    func run() {
        printBanner()
        let trusted = injector.promptAccessibilityIfNeeded()
        if !trusted {
            print("[warn] Accessibility permission is required for global hotkey and text injection.")
            print("[hint] Grant permission in System Settings > Privacy & Security > Accessibility.")
        }

        hotkeyMonitor = HotkeyMonitor(
            hotkey: config.hotkey,
            onPressed: { [weak self] in
                Task { @MainActor in
                    await self?.handleHotkeyPressed()
                }
            },
            onReleased: { [weak self] in
                Task { @MainActor in
                    await self?.handleHotkeyReleased()
                }
            }
        )

        hotkeyMonitor?.start()
        print("[ready] Waiting for hotkey: \(config.hotkey.display)")
    }

    private func handleHotkeyPressed() async {
        guard !isRecording else {
            return
        }

        let permissionsGranted = await transcriber.ensurePermissions()
        guard permissionsGranted else {
            print("[error] Speech/Microphone permission denied.")
            return
        }

        do {
            try transcriber.startRecording()
            isRecording = true
            print("[recording] Speak now...")
        } catch {
            print("[error] Failed to start recording: \(error)")
        }
    }

    private func handleHotkeyReleased() async {
        guard isRecording else {
            return
        }
        isRecording = false

        let raw = await transcriber.stopRecording()
        let guarded = textGuard.apply(raw: raw)
        guard !guarded.text.isEmpty else {
            print("[skip] Empty transcript")
            return
        }

        if guarded.fellBackToRaw {
            print("[guard] Format-only attempt changed semantics. Fallback to raw.")
        }

        if config.dryRun {
            print("[dry-run] \(guarded.text)")
            return
        }

        do {
            try injector.insert(text: guarded.text)
            print("[inserted] \(guarded.text)")
        } catch {
            print("[error] Failed to inject text: \(error)")
        }
    }

    private func printBanner() {
        print("verbatim-flow")
        print("mode=\(config.mode.rawValue) locale=\(config.localeIdentifier) hotkey=\(config.hotkey.display)")
        print("release hotkey to transcribe and insert")
    }
}
