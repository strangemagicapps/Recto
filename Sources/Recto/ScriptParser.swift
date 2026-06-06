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
///
/// > Note: Plain-text `parse(_:title:)` produces no *display-only* tokens:
/// > every token is both displayed and matched, so the display and match
/// > arrays stay 1:1 and each ``ParsedScript/DisplayWord`` has a non-nil
/// > ``ParsedScript/DisplayWord/matchIndex``. To mark tokens that are shown
/// > but never matched (for example a sound cue that is surtitled but never
/// > spoken aloud), use ``parse(segments:title:)`` with segments flagged
/// > ``ScriptSegment/isMatchable`` `false`.
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
        // Plain text is all matchable: every token is both shown and matched,
        // so the display and match arrays stay 1:1.
        appendTokens(of: rawText,
                     matchable: true,
                     into: &displayWords,
                     normalisedWords: &normalisedWords)
        return ParsedScript(
            title: title,
            displayWords: displayWords,
            normalisedWords: normalisedWords
        )
    }

    /// Parses an ordered list of ``ScriptSegment`` into a ``ParsedScript``,
    /// one segment per display line.
    ///
    /// Tokens from a segment with ``ScriptSegment/isMatchable`` `false` become
    /// *display-only* words: they appear in ``ParsedScript/displayWords`` with a
    /// `nil` ``ParsedScript/DisplayWord/matchIndex`` and contribute nothing to
    /// ``ParsedScript/normalisedWords``, so the matcher shows them but never
    /// expects to hear them (a sound cue, say). Matchable segments behave just
    /// like ``parse(_:title:)``.
    ///
    /// Segments are separated by a single line break in the display stream;
    /// empty segments (no tokens) are skipped without inserting a break.
    ///
    /// - Parameters:
    ///   - segments: The script's segments, in document order.
    ///   - title: A human-readable title. Defaults to the empty string.
    /// - Returns: A parsed value whose match stream omits display-only tokens.
    public static nonisolated func parse(
        segments: [ScriptSegment],
        title: String = ""
    ) -> ParsedScript {
        var displayWords: [ParsedScript.DisplayWord] = []
        var normalisedWords: [String] = []

        for segment in segments {
            let countBefore = displayWords.count
            appendTokens(of: segment.text,
                         matchable: segment.isMatchable,
                         into: &displayWords,
                         normalisedWords: &normalisedWords)

            // End the previous segment's line where this one begins, but only
            // once this segment actually contributed words — so empty segments
            // don't inject blank lines and the final word keeps no trailing
            // break (matching `parse(_:title:)`).
            if displayWords.count > countBefore, countBefore > 0 {
                let boundary = countBefore - 1
                let previous = displayWords[boundary]
                if previous.trailingNewlines == 0 {
                    displayWords[boundary] = ParsedScript.DisplayWord(
                        id: previous.id,
                        matchIndex: previous.matchIndex,
                        text: previous.text,
                        trailingSpace: false,
                        trailingNewlines: 1
                    )
                }
            }
        }

        return ParsedScript(
            title: title,
            displayWords: displayWords,
            normalisedWords: normalisedWords
        )
    }

    /// Tokenises `text` on Unicode whitespace and appends the tokens to the
    /// running display/normalised arrays. When `matchable` is `false` the tokens
    /// are display-only: they get a `nil` `matchIndex` and add nothing to
    /// `normalisedWords`.
    private static nonisolated func appendTokens(
        of text: String,
        matchable: Bool,
        into displayWords: inout [ParsedScript.DisplayWord],
        normalisedWords: inout [String]
    ) {
        let scalars = text.unicodeScalars
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

            var newlineCount = 0
            var hasSpace = false
            var previousWasCarriageReturn = false
            while index < end, scalars[index].properties.isWhitespace {
                let scalar = scalars[index]
                if CharacterSet.newlines.contains(scalar) {
                    // Count logical line breaks: a CRLF pair is one break,
                    // so don't double-count the "\n" that follows a "\r".
                    if !(scalar == "\n" && previousWasCarriageReturn) {
                        newlineCount += 1
                    }
                    previousWasCarriageReturn = scalar == "\r"
                } else {
                    hasSpace = true
                    previousWasCarriageReturn = false
                }
                index = scalars.index(after: index)
            }

            let matchIndex: Int?
            if matchable {
                matchIndex = normalisedWords.count
                normalisedWords.append(normalise(tokenSlice))
            } else {
                matchIndex = nil
            }
            displayWords.append(
                ParsedScript.DisplayWord(
                    id: displayWords.count,
                    matchIndex: matchIndex,
                    text: String(tokenSlice),
                    trailingSpace: hasSpace && newlineCount == 0,
                    trailingNewlines: newlineCount
                )
            )
        }
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
