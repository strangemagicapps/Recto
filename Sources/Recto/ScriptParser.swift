import Foundation

/// A stateless parser that turns raw script text into a ``ParsedScript``.
///
/// The parser tokenises on Unicode whitespace, preserving line breaks
/// through ``ParsedScript/DisplayWord/trailingNewline``. For each token
/// it produces:
///
/// - a *display* form, with the original punctuation and case intact, and
/// - a *normalised* form — lowercased, with leading and trailing
///   punctuation stripped. Internal punctuation is preserved, so
///   `"don't"` normalises to `"don't"` and `"rock'n'roll"` to
///   `"rock'n'roll"`. Both straight (`'`) and curly (`\u{2019}`)
///   apostrophes are treated identically.
///
/// `ScriptParser` keeps no state and may be called from any isolation
/// context.
public enum ScriptParser {
    /// Parses `rawText` into a ``ParsedScript``.
    ///
    /// - Parameters:
    ///   - rawText: The script's source text. May contain any Unicode
    ///     content; line breaks are preserved as
    ///     ``ParsedScript/DisplayWord/trailingNewline``.
    ///   - title: A human-readable title for the script. Defaults to
    ///     the empty string.
    /// - Returns: A parsed value containing parallel display and
    ///   normalised token arrays.
    public static nonisolated func parse(
        _ rawText: String,
        title: String = ""
    ) -> ParsedScript {
        var displayWords: [ParsedScript.DisplayWord] = []
        var normalisedWords: [String] = []

        let scalars = Array(rawText.unicodeScalars)
        let count = scalars.count
        var index = 0

        while index < count {
            while index < count, scalars[index].properties.isWhitespace {
                index += 1
            }
            guard index < count else { break }

            let tokenStart = index
            while index < count, !scalars[index].properties.isWhitespace {
                index += 1
            }
            let tokenScalars = scalars[tokenStart..<index]
            let tokenText = String(String.UnicodeScalarView(tokenScalars))

            var hasNewline = false
            var hasSpace = false
            while index < count, scalars[index].properties.isWhitespace {
                let scalar = scalars[index]
                if isNewline(scalar) {
                    hasNewline = true
                } else {
                    hasSpace = true
                }
                index += 1
            }

            let id = normalisedWords.count
            normalisedWords.append(normalise(tokenScalars))
            displayWords.append(
                ParsedScript.DisplayWord(
                    id: id,
                    text: tokenText,
                    trailingSpace: hasSpace && !hasNewline,
                    trailingNewline: hasNewline
                )
            )
        }

        return ParsedScript(
            title: title,
            displayWords: displayWords,
            normalisedWords: normalisedWords
        )
    }

    private static nonisolated func normalise(
        _ scalars: ArraySlice<Unicode.Scalar>
    ) -> String {
        var start = scalars.startIndex
        var end = scalars.endIndex
        while start < end, !isAlphanumeric(scalars[start]) {
            start += 1
        }
        while end > start, !isAlphanumeric(scalars[end - 1]) {
            end -= 1
        }
        guard start < end else { return "" }
        let trimmed = String(String.UnicodeScalarView(scalars[start..<end]))
        return trimmed.lowercased()
    }

    private static nonisolated func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar)
    }

    private static nonisolated func isNewline(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x000A, 0x000B, 0x000C, 0x000D, 0x0085, 0x2028, 0x2029:
            return true
        default:
            return false
        }
    }
}
