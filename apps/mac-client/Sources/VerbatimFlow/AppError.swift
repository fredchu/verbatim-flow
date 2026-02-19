import Foundation

enum AppError: Error, CustomStringConvertible {
    case speechRecognizerUnavailable(String)
    case speechServiceUnavailable
    case eventSourceCreationFailed
    case eventCreationFailed
    case accessibilityPermissionRequired

    var description: String {
        switch self {
        case .speechRecognizerUnavailable(let locale):
            return "Speech recognizer is unavailable for locale: \(locale)"
        case .speechServiceUnavailable:
            return "Speech service is not available right now"
        case .eventSourceCreationFailed:
            return "Failed to create event source"
        case .eventCreationFailed:
            return "Failed to create keyboard event"
        case .accessibilityPermissionRequired:
            return "Accessibility permission is required for text injection"
        }
    }
}
