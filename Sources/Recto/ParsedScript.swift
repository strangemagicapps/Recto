import Foundation

/// A parsed script: a value type holding the original title, a
/// display-ready token list, and a parallel normalised token list used
/// for matching against speech transcripts.
///
/// Construct a ``ParsedScript`` via ``ScriptParser/parse(_:title:)``;
/// the type has no public initialiser.
///
/// ``ParsedScript`` is fully `Sendable` and may be passed freely between
/// isolation domains.
public nonisolated struct ParsedScript: Sendable {
    /// The script's human-readable title, supplied by the caller. Empty
    /// by default.
    public let title: String

    /// Tokens in the order they appear in the source text, each carrying
    /// the original surface form plus the trailing whitespace it was
    /// followed by. Suitable for rendering the script verbatim.
    public let displayWords: [DisplayWord]

    /// Tokens normalised for matching: lowercased, with leading and
    /// trailing punctuation stripped. Internal apostrophes are retained
    /// so that contractions such as `"don't"` remain a single token.
    ///
    /// This array holds *only* matchable (spoken) tokens. Display-only
    /// tokens — speaker names, stage directions, scene headings — appear
    /// in ``displayWords`` with a `nil`
    /// ``DisplayWord/matchIndex`` and have no entry here, so
    /// `normalisedWords` may be shorter than ``displayWords``. Each
    /// matchable ``DisplayWord`` carries the index of its entry in this
    /// array as its ``DisplayWord/matchIndex``.
    public let normalisedWords: [String]

    /// Reverse lookup from a `normalisedWords` index to the position in
    /// ``displayWords`` that renders it. Precomputed at initialisation so
    /// ``displayIndex(forMatchIndex:)`` is O(1).
    private let matchToDisplay: [Int]

    /// A single token from a ``ParsedScript``.
    ///
    /// Pairs the original surface form (with punctuation and case
    /// preserved) against the trailing whitespace that followed it in
    /// the source, so consumers can reconstruct the script's visual
    /// layout without re-parsing.
    public struct DisplayWord: Sendable, Identifiable {
        /// This word's position in the parent script's
        /// ``ParsedScript/displayWords`` array, in display order.
        ///
        /// To find the matchable word's position instead, use
        /// ``matchIndex``.
        public let id: Int

        /// Index of this word in the parent script's
        /// ``ParsedScript/normalisedWords`` array, or `nil` when the token
        /// is display-only (a speaker name, stage direction, or scene
        /// heading) and is never matched against speech.
        public let matchIndex: Int?

        /// The original token, with punctuation and case intact —
        /// e.g. `"today,"`, `"\u{201C}Hello\u{201D}"`.
        public let text: String

        /// `true` when the token was followed by non-newline whitespace
        /// in the source — typically a space between words on the same
        /// line. Mutually exclusive with ``trailingNewline``.
        public let trailingSpace: Bool

        /// The number of consecutive line breaks that followed the token
        /// in the source: `0` when the next token is on the same line,
        /// `1` for an ordinary line break, and `2` or more for a blank
        /// line / stanza break. CRLF (`"\r\n"`) counts as a single break.
        /// Use this to render stanza or paragraph gaps back into the
        /// displayed script.
        public let trailingNewlines: Int

        /// `true` when the token's trailing whitespace contained at
        /// least one line break. Use this to render line breaks back
        /// into the displayed script. Derived from ``trailingNewlines``;
        /// see it to distinguish a single break from a stanza gap.
        public var trailingNewline: Bool { trailingNewlines > 0 }

        init(id: Int, matchIndex: Int?, text: String, trailingSpace: Bool, trailingNewlines: Int) {
            self.id = id
            self.matchIndex = matchIndex
            self.text = text
            self.trailingSpace = trailingSpace
            self.trailingNewlines = trailingNewlines
        }
    }

    init(title: String, displayWords: [DisplayWord], normalisedWords: [String]) {
        self.title = title
        self.displayWords = displayWords
        self.normalisedWords = normalisedWords

        // Build the reverse map from each matchable word back to its
        // position in display order, so the UI can locate the cursor.
        var matchToDisplay = [Int](repeating: 0, count: normalisedWords.count)
        for word in displayWords {
            if let matchIndex = word.matchIndex, matchToDisplay.indices.contains(matchIndex) {
                matchToDisplay[matchIndex] = word.id
            }
        }
        self.matchToDisplay = matchToDisplay
    }

    /// The position in ``displayWords`` that renders the normalised word
    /// at `matchIndex`.
    ///
    /// Use this to translate a matcher cursor — a
    /// ``ScriptTracker/currentMatchIndex``, which indexes
    /// ``normalisedWords`` — back to a position in the displayed script.
    ///
    /// - Parameter matchIndex: An index into ``normalisedWords``.
    /// - Returns: The corresponding ``DisplayWord/id``, or `nil` when
    ///   `matchIndex` lies outside `0 ..< normalisedWords.count` (for
    ///   example, when the cursor is parked one past the final word).
    public func displayIndex(forMatchIndex matchIndex: Int) -> Int? {
        guard matchToDisplay.indices.contains(matchIndex) else { return nil }
        return matchToDisplay[matchIndex]
    }
}
