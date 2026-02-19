import Foundation

enum PermissionState: String {
    case notDetermined = "Not Determined"
    case authorized = "Authorized"
    case denied = "Denied"
    case restricted = "Restricted"
    case unsupported = "Unsupported"
}

struct PermissionSnapshot {
    let speech: PermissionState
    let microphone: PermissionState
    let accessibilityTrusted: Bool

    var summaryLine: String {
        let accessibility = accessibilityTrusted ? "Authorized" : "Denied"
        return "Mic: \(microphone.rawValue) | Speech: \(speech.rawValue) | Accessibility: \(accessibility)"
    }

    var isReadyForHotkeyDictation: Bool {
        speech == .authorized && microphone == .authorized && accessibilityTrusted
    }
}
