import Foundation

struct TerminologyRules {
    struct Replacement {
        let source: String
        let target: String
        let regex: NSRegularExpression
    }

    let hints: [String]
    let replacements: [Replacement]
}

struct TerminologyApplyResult {
    let text: String
    let appliedRules: [String]
}

enum TerminologyDictionary {
    private static let applicationSupportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("VerbatimFlow", isDirectory: true)
    }()

    static let fileURL: URL = applicationSupportDirectory.appendingPathComponent("terminology.txt")

    private static let defaultFileTemplate: String = """
# VerbatimFlow terminology dictionary
# One line per rule:
# 1) term               -> add term to ASR contextual hints
# 2) source => target   -> replace source with target after transcription
#
# Example:
Commit
Token
Workflow
Comet => Commit
"""

    static func ensureDictionaryFileExists() {
        do {
            try FileManager.default.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
            guard !FileManager.default.fileExists(atPath: fileURL.path) else {
                return
            }
            try defaultFileTemplate.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            RuntimeLogger.log("[terminology] failed to ensure dictionary file: \(error)")
        }
    }

    static func loadRules() -> TerminologyRules {
        ensureDictionaryFileExists()

        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return TerminologyRules(hints: [], replacements: [])
        }

        var hints: [String] = []
        var hintSeen: Set<String> = []
        var replacements: [TerminologyRules.Replacement] = []

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }

            if let replacement = parseReplacement(from: trimmed) {
                replacements.append(replacement)
                appendHint(replacement.target, hints: &hints, hintSeen: &hintSeen)
                continue
            }

            appendHint(trimmed, hints: &hints, hintSeen: &hintSeen)
        }

        return TerminologyRules(hints: hints, replacements: replacements)
    }

    static func applyReplacements(to text: String, replacements: [TerminologyRules.Replacement]) -> TerminologyApplyResult {
        guard !text.isEmpty, !replacements.isEmpty else {
            return TerminologyApplyResult(text: text, appliedRules: [])
        }

        var output = text
        var appliedRules: [String] = []
        for replacement in replacements {
            let fullRange = NSRange(output.startIndex..<output.endIndex, in: output)
            let replaced = replacement.regex.stringByReplacingMatches(
                in: output,
                options: [],
                range: fullRange,
                withTemplate: NSRegularExpression.escapedTemplate(for: replacement.target)
            )

            if replaced != output {
                appliedRules.append("\(replacement.source) => \(replacement.target)")
                output = replaced
            }
        }

        return TerminologyApplyResult(text: output, appliedRules: appliedRules)
    }

    private static func parseReplacement(from line: String) -> TerminologyRules.Replacement? {
        let parts = line.components(separatedBy: "=>")
        guard parts.count == 2 else {
            return nil
        }

        let source = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let target = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !target.isEmpty else {
            return nil
        }

        let escaped = NSRegularExpression.escapedPattern(for: source)
        let needsWordBoundary = source.rangeOfCharacter(from: CharacterSet.alphanumerics) != nil
        let pattern = needsWordBoundary
            ? "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])"
            : escaped

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        return TerminologyRules.Replacement(source: source, target: target, regex: regex)
    }

    private static func appendHint(_ value: String, hints: inout [String], hintSeen: inout Set<String>) {
        let key = value.lowercased()
        guard !key.isEmpty, !hintSeen.contains(key) else {
            return
        }
        hintSeen.insert(key)
        hints.append(value)
    }
}
