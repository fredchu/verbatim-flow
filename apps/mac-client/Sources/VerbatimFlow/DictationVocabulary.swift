import Foundation

enum DictationVocabulary {
    enum CorrectionPolicy: Equatable {
        case always
        case contextual(keywords: [String])
    }

    private struct TermProfile {
        let term: String
        let includeInASRHints: Bool
        let correctionPolicy: CorrectionPolicy
    }

    private static let termProfiles: [TermProfile] = [
        TermProfile(term: "Commit", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Branch", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Repository", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Pull Request", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "PR", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Release", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Token", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Context", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Prompt", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Workflow", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "BROLL", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "B-roll", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "iTerm2", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Terminal", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Git", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "GitHub", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Mac", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Whisper", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "VerbatimFlow", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Raycast", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Wispr", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Tabless", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Typeless", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Claude", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "GPT", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "GPT-5", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "OpenAI", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Anthropic", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Gemini", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "YouTube", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(
            term: "Tana",
            includeInASRHints: false,
            correctionPolicy: .contextual(
                keywords: ["笔记", "知识", "项目", "标签", "节点", "工作区", "数据库", "app", "软件", "工具", "obsidian", "notion", "readwise", "workspace", "node", "tag"]
            )
        )
    ]

    static let chineseAssistTerms: [String] = [
        "中文",
        "英文",
        "中英文混合",
        "识别准确率",
        "剪贴板",
        "文本框",
        "插入",
        "提交",
        "分支",
        "仓库",
        "拉取请求"
    ]

    static func contextualHints(localeIdentifier: String, customHints: [String]) -> [String] {
        let baseHints = transcriptionPromptTerms(customHints: customHints)
        if localeIdentifier.lowercased().hasPrefix("zh") {
            return deduplicated(baseHints + chineseAssistTerms)
        }
        return baseHints
    }

    static func transcriptionPromptTerms(customHints: [String]) -> [String] {
        deduplicated(termProfiles.filter(\.includeInASRHints).map(\.term) + customHints)
    }

    static func fuzzyCorrectionTerms(customHints: [String]) -> [String] {
        deduplicated(termProfiles.map(\.term) + customHints)
    }

    static func correctionPolicy(for term: String) -> CorrectionPolicy {
        let key = normalizedTermKey(term)
        for profile in termProfiles {
            if normalizedTermKey(profile.term) == key {
                return profile.correctionPolicy
            }
        }
        return .always
    }

    private static func normalizedTermKey(_ term: String) -> String {
        term
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        output.reserveCapacity(values.count)

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(trimmed)
        }

        return output
    }
}
