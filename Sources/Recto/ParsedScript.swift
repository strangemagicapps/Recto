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
    /// The array is the same length as ``displayWords``; each
    /// ``DisplayWord/id`` is an index into this array.
    public let normalisedWords: [String]

    /// A single token from a ``ParsedScript``.
    ///
    /// Pairs the original surface form (with punctuation and case
    /// preserved) against the trailing whitespace that followed it in
    /// the source, so consumers can reconstruct the script's visual
    /// layout without re-parsing.
    public struct DisplayWord: Sendable, Identifiable {
        /// Index of this word in the parent script's
        /// ``ParsedScript/normalisedWords`` array.
        public let id: Int

        /// The original token, with punctuation and case intact —
        /// e.g. `"today,"`, `"\u{201C}Hello\u{201D}"`.
        public let text: String

        /// `true` when the token was followed by non-newline whitespace
        /// in the source — typically a space between words on the same
        /// line. Mutually exclusive with ``trailingNewline``.
        public let trailingSpace: Bool

        /// `true` when the token's trailing whitespace contained at
        /// least one line break. Use this to render line breaks back
        /// into the displayed script.
        public let trailingNewline: Bool

        init(id: Int, text: String, trailingSpace: Bool, trailingNewline: Bool) {
            self.id = id
            self.text = text
            self.trailingSpace = trailingSpace
            self.trailingNewline = trailingNewline
        }
    }

    init(title: String, displayWords: [DisplayWord], normalisedWords: [String]) {
        self.title = title
        self.displayWords = displayWords
        self.normalisedWords = normalisedWords
    }
}
