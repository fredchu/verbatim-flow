import Foundation

struct GuardedText {
    let text: String
    let fellBackToRaw: Bool
}

struct TextGuard {
    let mode: OutputMode

    func apply(raw: String) -> GuardedText {
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else {
            return GuardedText(text: "", fellBackToRaw: false)
        }

        switch mode {
        case .raw:
            return GuardedText(text: trimmedRaw, fellBackToRaw: false)
        case .formatOnly:
            let formatted = formatOnlyNormalize(trimmedRaw)
            if semanticallyEquivalent(lhs: trimmedRaw, rhs: formatted) {
                return GuardedText(text: formatted, fellBackToRaw: false)
            }
            return GuardedText(text: trimmedRaw, fellBackToRaw: true)
        }
    }

    private func formatOnlyNormalize(_ text: String) -> String {
        var output = text
        output = replace(output, pattern: "\\s+", template: " ")
        output = replace(output, pattern: "\\s+([,\\.!?;:，。！？；：])", template: "$1")
        output = replace(output, pattern: "([,\\.!?;:])(\\S)", template: "$1 $2")
        output = replace(output, pattern: "([，。！？；：])(\\s+)", template: "$1")
        output = replace(output, pattern: "\\s+([)\\]}>])", template: "$1")
        output = replace(output, pattern: "([(\\[<{])\\s+", template: "$1")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func semanticallyEquivalent(lhs: String, rhs: String) -> Bool {
        canonicalTokens(lhs) == canonicalTokens(rhs)
    }

    private func canonicalTokens(_ text: String) -> [String] {
        let punctuation = CharacterSet.punctuationCharacters
            .union(.symbols)
            .union(.whitespacesAndNewlines)

        var normalized = ""
        normalized.reserveCapacity(text.count)

        for scalar in text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).unicodeScalars {
            if punctuation.contains(scalar) {
                normalized.append(" ")
            } else {
                normalized.unicodeScalars.append(scalar)
            }
        }

        return normalized
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private func replace(_ input: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return input
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: template)
    }
}
