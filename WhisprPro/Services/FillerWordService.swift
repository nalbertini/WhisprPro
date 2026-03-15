import Foundation

struct FillerWordService {
    /// Common filler words across languages
    /// Matched as whole words (case-insensitive)
    private static let fillerPatterns: [String] = [
        // English
        "um", "uh", "uhh", "umm", "erm", "er", "ah", "ahh",
        "hmm", "hm", "mm", "mmm", "mhm",
        "you know", "like", "I mean", "sort of", "kind of",
        // Italian
        "ehm", "eh", "cioè", "tipo", "praticamente", "diciamo",
        // Spanish
        "este", "pues", "o sea",
        // French
        "euh", "bah", "ben", "hein",
        // German
        "äh", "ähm", "halt", "also",
    ]

    /// Words that should only be removed when standalone (not part of a sentence)
    private static let standaloneOnly: Set<String> = [
        "like", "I mean", "sort of", "kind of",
        "cioè", "tipo", "praticamente", "diciamo",
        "este", "pues", "o sea",
        "halt", "also",
    ]

    /// Remove filler words from text
    static func removeFillersFrom(_ text: String) -> String {
        var result = text

        // First remove multi-word fillers
        for filler in fillerPatterns where filler.contains(" ") {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: filler))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // Then single-word fillers (only non-standalone ones, plus standalone at start/end)
        for filler in fillerPatterns where !filler.contains(" ") {
            if standaloneOnly.contains(filler) {
                // Only remove at start or end of segment
                let startPattern = "^\\s*\(NSRegularExpression.escapedPattern(for: filler))\\b[,.]?\\s*"
                let endPattern = "\\s*[,.]?\\b\(NSRegularExpression.escapedPattern(for: filler))\\s*$"
                for pattern in [startPattern, endPattern] {
                    if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                        result = regex.stringByReplacingMatches(
                            in: result,
                            range: NSRange(result.startIndex..., in: result),
                            withTemplate: ""
                        )
                    }
                }
            } else {
                // Remove everywhere as whole word, including surrounding commas
                let pattern = "\\s*,?\\s*\\b\(NSRegularExpression.escapedPattern(for: filler))\\b\\s*,?\\s*"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    result = regex.stringByReplacingMatches(
                        in: result,
                        range: NSRange(result.startIndex..., in: result),
                        withTemplate: " "
                    )
                }
            }
        }

        // Clean up multiple spaces and trim
        result = result.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespaces)

        // Capitalize first letter if needed
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }

        return result
    }
}
