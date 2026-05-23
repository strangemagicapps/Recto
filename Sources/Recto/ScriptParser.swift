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

        let scalars = rawText.unicodeScalars
        var index = scalars.startIndex
        let end = scalars.endIndex

        while index < end {
            while index < end, scalars[index].properties.isWhitespace {
                index = scalars.index(after: index)
            }
            guard index < end else { break }

            let tokenStart = index
            while index < end, !scalars[index].properties.isWhitespace {
                index = scalars.index(after: index)
            }
            let tokenSlice = scalars[tokenStart..<index]

            var hasNewline = false
            var hasSpace = false
            while index < end, scalars[index].properties.isWhitespace {
                if CharacterSet.newlines.contains(scalars[index]) {
                    hasNewline = true
                } else {
                    hasSpace = true
                }
                index = scalars.index(after: index)
            }

            // Plain-text input has no display-only tokens: every token is
            // both shown and matched, so each display word gets a non-nil
            // match index and the two arrays stay 1:1.
            let displayID = displayWords.count
            let matchIndex = normalisedWords.count
            normalisedWords.append(normalise(tokenSlice))
            displayWords.append(
                ParsedScript.DisplayWord(
                    id: displayID,
                    matchIndex: matchIndex,
                    text: String(tokenSlice),
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
        _ scalars: String.UnicodeScalarView.SubSequence
    ) -> String {
        let alphanumerics = CharacterSet.alphanumerics
        var start = scalars.startIndex
        var end = scalars.endIndex
        while start < end, !alphanumerics.contains(scalars[start]) {
            start = scalars.index(after: start)
        }
        while end > start {
            let prev = scalars.index(before: end)
            if alphanumerics.contains(scalars[prev]) { break }
            end = prev
        }
        guard start < end else { return "" }
        return String(scalars[start..<end]).lowercased()
    }
}
