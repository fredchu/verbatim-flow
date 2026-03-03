import Foundation

final class AppPreferences {
    static let systemLanguageToken = "system"

    private enum Key {
        static let mode = "verbatimflow.mode"
        static let hotkey = "verbatimflow.hotkey"
        static let languageSelection = "verbatimflow.languageSelection"
        static let recognitionEngine = "verbatimflow.recognitionEngine"
        static let whisperModel = "verbatimflow.whisperModel"
        static let openAIModel = "verbatimflow.openAIModel"
        static let qwenModel = "verbatimflow.qwenModel"
        static let llmBaseURL = "verbatimflow.llmBaseURL"
        static let punctuationModel = "verbatimflow.punctuationModel"
        static let punctuationPrompt = "verbatimflow.punctuationPrompt"
        static let localRewriteModel = "verbatimflow.localRewriteModel"
        static let localRewritePrompt = "verbatimflow.localRewritePrompt"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadMode() -> OutputMode? {
        guard let rawValue = defaults.string(forKey: Key.mode) else {
            return nil
        }
        return OutputMode(rawValue: rawValue)
    }

    func saveMode(_ mode: OutputMode) {
        defaults.set(mode.rawValue, forKey: Key.mode)
    }

    func loadHotkey() -> Hotkey? {
        guard let combo = defaults.string(forKey: Key.hotkey) else {
            return nil
        }
        return try? HotkeyParser.parse(combo: combo)
    }

    func saveHotkey(_ hotkey: Hotkey) {
        defaults.set(hotkey.display.lowercased(), forKey: Key.hotkey)
    }

    func loadLanguageSelection() -> String? {
        defaults.string(forKey: Key.languageSelection)
    }

    func saveLanguageSelection(_ value: String) {
        defaults.set(value, forKey: Key.languageSelection)
    }

    func loadRecognitionEngine() -> RecognitionEngine? {
        guard let rawValue = defaults.string(forKey: Key.recognitionEngine) else {
            return nil
        }
        return RecognitionEngine(rawValue: rawValue)
    }

    func saveRecognitionEngine(_ engine: RecognitionEngine) {
        defaults.set(engine.rawValue, forKey: Key.recognitionEngine)
    }

    func loadWhisperModel() -> WhisperModel? {
        guard let rawValue = defaults.string(forKey: Key.whisperModel) else {
            return nil
        }
        return WhisperModel(rawValue: rawValue)
    }

    func saveWhisperModel(_ model: WhisperModel) {
        defaults.set(model.rawValue, forKey: Key.whisperModel)
    }

    func loadOpenAIModel() -> OpenAITranscriptionModel? {
        guard let rawValue = defaults.string(forKey: Key.openAIModel) else {
            return nil
        }
        return OpenAITranscriptionModel(rawValue: rawValue)
    }

    func saveOpenAIModel(_ model: OpenAITranscriptionModel) {
        defaults.set(model.rawValue, forKey: Key.openAIModel)
    }

    func loadQwenModel() -> QwenModel? {
        guard let rawValue = defaults.string(forKey: Key.qwenModel) else {
            return nil
        }
        return QwenModel(rawValue: rawValue)
    }

    func saveQwenModel(_ model: QwenModel) {
        defaults.set(model.rawValue, forKey: Key.qwenModel)
    }

    // MARK: - LLM Settings

    func loadLLMBaseURL() -> String? {
        defaults.string(forKey: Key.llmBaseURL)
    }

    func saveLLMBaseURL(_ value: String) {
        defaults.set(value, forKey: Key.llmBaseURL)
    }

    func loadPunctuationModel() -> String? {
        defaults.string(forKey: Key.punctuationModel)
    }

    func savePunctuationModel(_ value: String) {
        defaults.set(value, forKey: Key.punctuationModel)
    }

    func loadPunctuationPrompt() -> String? {
        defaults.string(forKey: Key.punctuationPrompt)
    }

    func savePunctuationPrompt(_ value: String) {
        defaults.set(value, forKey: Key.punctuationPrompt)
    }

    func loadLocalRewriteModel() -> String? {
        defaults.string(forKey: Key.localRewriteModel)
    }

    func saveLocalRewriteModel(_ value: String) {
        defaults.set(value, forKey: Key.localRewriteModel)
    }

    func loadLocalRewritePrompt() -> String? {
        defaults.string(forKey: Key.localRewritePrompt)
    }

    func saveLocalRewritePrompt(_ value: String) {
        defaults.set(value, forKey: Key.localRewritePrompt)
    }

    func clearLLMSettings() {
        for key in [Key.llmBaseURL, Key.punctuationModel, Key.punctuationPrompt,
                    Key.localRewriteModel, Key.localRewritePrompt] {
            defaults.removeObject(forKey: key)
        }
    }
}
