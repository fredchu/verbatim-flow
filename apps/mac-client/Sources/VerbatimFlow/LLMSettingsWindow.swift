import AppKit
import Foundation

@MainActor
final class LLMSettingsWindow: NSWindow {

    // MARK: - Default values

    static let defaultBaseURL = "http://localhost:1234"
    static let defaultPunctuationModel = "qwen/qwen3-vl-8b"
    static let defaultPunctuationPrompt =
        "你是標點符號專家。請為以下中文語音辨識文字加上適當的全形標點符號（，。、？！：；「」『』《》）。只加標點，不改動任何文字內容。直接輸出結果，不要解釋。/no_think"
    static let defaultRewriteModel = "qwen/qwen3-vl-8b"
    static let defaultRewritePrompt = """
        你是 VerbatimFlow 本地校正模式。
        將語音轉錄的口語文字改寫為通順的書面語。
        規則：
        - 保持原意、事實、數字、專有名詞不變。
        - 不添加原文沒有的資訊。
        - 去除口語贅詞（嗯、啊、然後、就是說、對、那個）和明顯重複。
        - 保持與輸入相同的語言（中文維持中文，中英混合維持混合）。
        - 使用台灣繁體中文用語和全形標點符號（，。！？；：）。
        - 僅輸出改寫後的純文字，不要 markdown，不要解釋。 /no_think
        """

    // MARK: - UI controls

    private let baseURLField = NSTextField()
    private let punctuationModelField = NSTextField()
    private let punctuationPromptView = NSTextView()
    private let rewriteModelField = NSTextField()
    private let rewritePromptView = NSTextView()

    private let preferences: AppPreferences

    // MARK: - Init

    init(preferences: AppPreferences) {
        self.preferences = preferences
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.title = "LLM Settings"
        self.isReleasedWhenClosed = false
        self.minSize = NSSize(width: 480, height: 580)

        buildUI()
        loadValues()
    }

    // MARK: - Build UI

    private func buildUI() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 620))
        self.contentView = contentView

        let margin: CGFloat = 20
        let fieldWidth: CGFloat = 500 - margin * 2
        let labelHeight: CGFloat = 18
        let fieldHeight: CGFloat = 24
        let promptHeight: CGFloat = 90
        let sectionSpacing: CGFloat = 16
        let itemSpacing: CGFloat = 6
        let monospace = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        var y: CGFloat = 620 - margin

        // ── General ──
        y -= labelHeight
        contentView.addSubview(makeSectionHeader("General", frame: NSRect(x: margin, y: y, width: fieldWidth, height: labelHeight)))

        y -= (itemSpacing + labelHeight)
        contentView.addSubview(makeLabel("LM Studio Base URL", frame: NSRect(x: margin, y: y, width: fieldWidth, height: labelHeight)))

        y -= (itemSpacing + fieldHeight)
        configureTextField(baseURLField, frame: NSRect(x: margin, y: y, width: fieldWidth, height: fieldHeight), font: monospace)
        contentView.addSubview(baseURLField)

        // ── Punctuation ──
        y -= (sectionSpacing + labelHeight)
        contentView.addSubview(makeSectionHeader("Punctuation", frame: NSRect(x: margin, y: y, width: fieldWidth, height: labelHeight)))

        y -= (itemSpacing + labelHeight)
        contentView.addSubview(makeLabel("Model ID", frame: NSRect(x: margin, y: y, width: fieldWidth, height: labelHeight)))

        y -= (itemSpacing + fieldHeight)
        configureTextField(punctuationModelField, frame: NSRect(x: margin, y: y, width: fieldWidth, height: fieldHeight), font: monospace)
        contentView.addSubview(punctuationModelField)

        y -= (itemSpacing + labelHeight)
        contentView.addSubview(makeLabel("System Prompt", frame: NSRect(x: margin, y: y, width: fieldWidth, height: labelHeight)))

        y -= (itemSpacing + promptHeight)
        let punctuationScrollView = makeScrollableTextView(punctuationPromptView, frame: NSRect(x: margin, y: y, width: fieldWidth, height: promptHeight), font: monospace)
        contentView.addSubview(punctuationScrollView)

        // ── Local Rewrite ──
        y -= (sectionSpacing + labelHeight)
        contentView.addSubview(makeSectionHeader("Local Rewrite", frame: NSRect(x: margin, y: y, width: fieldWidth, height: labelHeight)))

        y -= (itemSpacing + labelHeight)
        contentView.addSubview(makeLabel("Model ID", frame: NSRect(x: margin, y: y, width: fieldWidth, height: labelHeight)))

        y -= (itemSpacing + fieldHeight)
        configureTextField(rewriteModelField, frame: NSRect(x: margin, y: y, width: fieldWidth, height: fieldHeight), font: monospace)
        contentView.addSubview(rewriteModelField)

        y -= (itemSpacing + labelHeight)
        contentView.addSubview(makeLabel("System Prompt", frame: NSRect(x: margin, y: y, width: fieldWidth, height: labelHeight)))

        y -= (itemSpacing + promptHeight)
        let rewriteScrollView = makeScrollableTextView(rewritePromptView, frame: NSRect(x: margin, y: y, width: fieldWidth, height: promptHeight), font: monospace)
        contentView.addSubview(rewriteScrollView)

        // ── Buttons ──
        y -= (sectionSpacing + 32)
        let buttonY = y

        let resetButton = NSButton(title: "Reset Defaults", target: self, action: #selector(resetDefaults))
        resetButton.frame = NSRect(x: margin, y: buttonY, width: 120, height: 32)
        resetButton.bezelStyle = .rounded
        contentView.addSubview(resetButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveButton.frame = NSRect(x: 500 - margin - 80, y: buttonY, width: 80, height: 32)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)
    }

    // MARK: - UI helpers

    private func makeSectionHeader(_ title: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: "\u{2500}\u{2500} \(title) \u{2500}\u{2500}")
        label.frame = frame
        label.font = NSFont.boldSystemFont(ofSize: 13)
        label.textColor = .labelColor
        return label
    }

    private func makeLabel(_ text: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func configureTextField(_ field: NSTextField, frame: NSRect, font: NSFont) {
        field.frame = frame
        field.font = font
        field.isEditable = true
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
    }

    private func makeScrollableTextView(_ textView: NSTextView, frame: NSRect, font: NSFont) -> NSScrollView {
        let scrollView = NSScrollView(frame: frame)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true

        textView.frame = NSRect(x: 0, y: 0, width: frame.width - 2, height: frame.height - 2)
        textView.font = font
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: frame.height - 2)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        return scrollView
    }

    // MARK: - Load / Save / Reset

    func loadValues() {
        baseURLField.stringValue = preferences.loadLLMBaseURL() ?? Self.defaultBaseURL
        punctuationModelField.stringValue = preferences.loadPunctuationModel() ?? Self.defaultPunctuationModel
        punctuationPromptView.string = preferences.loadPunctuationPrompt() ?? Self.defaultPunctuationPrompt
        rewriteModelField.stringValue = preferences.loadLocalRewriteModel() ?? Self.defaultRewriteModel
        rewritePromptView.string = preferences.loadLocalRewritePrompt() ?? Self.defaultRewritePrompt
    }

    @objc private func saveSettings() {
        preferences.saveLLMBaseURL(baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        preferences.savePunctuationModel(punctuationModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        preferences.savePunctuationPrompt(punctuationPromptView.string.trimmingCharacters(in: .whitespacesAndNewlines))
        preferences.saveLocalRewriteModel(rewriteModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        preferences.saveLocalRewritePrompt(rewritePromptView.string.trimmingCharacters(in: .whitespacesAndNewlines))
        close()
    }

    @objc private func resetDefaults() {
        preferences.clearLLMSettings()
        loadValues()
    }
}
