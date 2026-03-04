import Foundation

struct MixedLanguageEnhancementResult {
    let text: String
    let appliedRules: [String]
}

enum MixedLanguageEnhancer {
    private static let englishTokenRegex = try? NSRegularExpression(pattern: "[A-Za-z][A-Za-z0-9\\-']*", options: [])
    private static let hanCharacterRegex = try? NSRegularExpression(pattern: "\\p{Han}", options: [])
    private static let hanTokenRegex = try? NSRegularExpression(pattern: "[\\p{Han}]{2,6}", options: [])

    static func apply(text: String, localeIdentifier: String, vocabularyHints: [String]) -> MixedLanguageEnhancementResult {
        guard !text.isEmpty else {
            return MixedLanguageEnhancementResult(text: text, appliedRules: [])
        }

        guard localeIdentifier.lowercased().hasPrefix("zh"), containsHanCharacter(text) else {
            return MixedLanguageEnhancementResult(text: text, appliedRules: [])
        }

        let canonicalTerms = normalizedCanonicalTerms(from: vocabularyHints)
        guard !canonicalTerms.isEmpty else {
            return MixedLanguageEnhancementResult(text: text, appliedRules: [])
        }

        var output = text
        var appliedRules: [String] = []

        if containsEnglishToken(text) {
            let englishCorrections = applyEnglishTokenCorrections(text: output, candidates: canonicalTerms)
            output = englishCorrections.text
            appliedRules.append(contentsOf: englishCorrections.appliedRules)
        }

        let hanCorrections = applyHanTokenCorrections(text: output, candidates: canonicalTerms)
        output = hanCorrections.text
        appliedRules.append(contentsOf: hanCorrections.appliedRules)

        return MixedLanguageEnhancementResult(text: output, appliedRules: appliedRules)
    }

    private static func containsHanCharacter(_ text: String) -> Bool {
        guard let regex = hanCharacterRegex else { return false }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func containsEnglishToken(_ text: String) -> Bool {
        guard let regex = englishTokenRegex else { return false }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func applyEnglishTokenCorrections(text: String, candidates: [String: String]) -> MixedLanguageEnhancementResult {
        guard let regex = englishTokenRegex else {
            return MixedLanguageEnhancementResult(text: text, appliedRules: [])
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else {
            return MixedLanguageEnhancementResult(text: text, appliedRules: [])
        }

        var output = text
        var appliedRules: [String] = []

        for match in matches.reversed() {
            guard match.range.location != NSNotFound else { continue }

            let range = Range(match.range, in: output)
            guard let tokenRange = range else { continue }
            let token = String(output[tokenRange])
            let normalized = token.lowercased()

            guard candidates[normalized] == nil else {
                continue
            }

            guard let candidate = bestCandidate(for: normalized, candidates: candidates) else {
                continue
            }

            let replacement = adaptCase(reference: token, candidate: candidate)
            output.replaceSubrange(tokenRange, with: replacement)
            appliedRules.append("\(token) -> \(replacement)")
        }

        return MixedLanguageEnhancementResult(text: output, appliedRules: appliedRules.reversed())
    }

    private static func applyHanTokenCorrections(text: String, candidates: [String: String]) -> MixedLanguageEnhancementResult {
        guard let regex = hanTokenRegex else {
            return MixedLanguageEnhancementResult(text: text, appliedRules: [])
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else {
            return MixedLanguageEnhancementResult(text: text, appliedRules: [])
        }

        var output = text
        var appliedRules: [String] = []

        let phoneticTerms = normalizedPhoneticTerms(from: candidates)
        guard !phoneticTerms.isEmpty else {
            return MixedLanguageEnhancementResult(text: text, appliedRules: [])
        }

        for match in matches.reversed() {
            guard match.range.location != NSNotFound else { continue }
            let range = Range(match.range, in: output)
            guard let tokenRange = range else { continue }
            let token = String(output[tokenRange])
            let latin = latinSkeleton(for: token)
            guard latin.count >= 4 else { continue }

            guard let candidate = bestPhoneticCandidate(for: latin, candidates: phoneticTerms) else {
                continue
            }

            output.replaceSubrange(tokenRange, with: candidate)
            appliedRules.append("\(token) -> \(candidate)")
        }

        return MixedLanguageEnhancementResult(text: output, appliedRules: appliedRules.reversed())
    }

    private static func normalizedCanonicalTerms(from rawHints: [String]) -> [String: String] {
        var table: [String: String] = [:]
        for hint in rawHints {
            let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.contains(" ") {
                continue
            }

            guard trimmed.rangeOfCharacter(from: CharacterSet.letters) != nil else {
                continue
            }

            table[trimmed.lowercased()] = trimmed
        }
        return table
    }

    private static func normalizedPhoneticTerms(from candidates: [String: String]) -> [String: String] {
        var table: [String: String] = [:]
        for (_, original) in candidates {
            let normalized = original.lowercased()
            let lettersOnly = normalized.replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
            guard lettersOnly.count >= 4 else {
                continue
            }
            table[lettersOnly] = original
        }
        return table
    }

    private static func bestCandidate(for token: String, candidates: [String: String]) -> String? {
        var best: (term: String, distance: Int)?

        for (normalized, original) in candidates {
            guard normalized.first == token.first else {
                continue
            }

            if abs(normalized.count - token.count) > 2 {
                continue
            }

            let distance = levenshtein(token, normalized)
            if distance > maxDistance(for: normalized.count) {
                continue
            }

            if let currentBest = best {
                if distance < currentBest.distance {
                    best = (original, distance)
                }
            } else {
                best = (original, distance)
            }
        }

        return best?.term
    }

    private static func maxDistance(for length: Int) -> Int {
        if length <= 4 {
            return 1
        }
        if length <= 8 {
            return 2
        }
        return 3
    }

    private static func maxPhoneticDistance(for length: Int) -> Int {
        if length <= 5 {
            return 2
        }
        if length <= 8 {
            return 3
        }
        return 4
    }

    private static func bestPhoneticCandidate(for tokenLatin: String, candidates: [String: String]) -> String? {
        var best: (term: String, distance: Int)?

        for (normalized, original) in candidates {
            guard normalized.first == tokenLatin.first else {
                continue
            }

            if abs(normalized.count - tokenLatin.count) > 5 {
                continue
            }

            let distance = levenshtein(tokenLatin, normalized)
            if distance > maxPhoneticDistance(for: normalized.count) {
                continue
            }

            if let currentBest = best {
                if distance < currentBest.distance {
                    best = (original, distance)
                }
            } else {
                best = (original, distance)
            }
        }

        return best?.term
    }

    private static func adaptCase(reference: String, candidate: String) -> String {
        if reference.rangeOfCharacter(from: CharacterSet.letters) == nil {
            return candidate
        }

        if reference.uppercased() == reference {
            return candidate.uppercased()
        }

        if let first = reference.first, String(first).uppercased() == String(first), reference.dropFirst().lowercased() == reference.dropFirst() {
            let head = String(candidate.prefix(1)).uppercased()
            let tail = String(candidate.dropFirst()).lowercased()
            return head + tail
        }

        return candidate.lowercased()
    }

    private static func latinSkeleton(for text: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        let toLatin = CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        if toLatin {
            _ = CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        }

        return (mutable as String)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)

        if lhsChars.isEmpty { return rhsChars.count }
        if rhsChars.isEmpty { return lhsChars.count }

        var previous = Array(0...rhsChars.count)
        var current = Array(repeating: 0, count: rhsChars.count + 1)

        for i in 1...lhsChars.count {
            current[0] = i
            for j in 1...rhsChars.count {
                let substitutionCost = lhsChars[i - 1] == rhsChars[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + substitutionCost
                )
            }
            previous = current
        }

        return previous[rhsChars.count]
    }
}
