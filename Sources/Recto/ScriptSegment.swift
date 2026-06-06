/// One line of a script handed to ``ScriptParser/parse(segments:title:)``.
///
/// A segment is shown on its own display line. When ``isMatchable`` is `false`
/// its words are *display-only*: surfaced to the reader but excluded from the
/// match stream, so the matcher never expects to hear them — a sound cue that
/// is surtitled but never spoken aloud, for example.
public struct ScriptSegment: Sendable, Equatable {
    /// The segment's source text (a single line).
    public var text: String

    /// Whether the segment's words enter the match stream. `false` makes them
    /// display-only (a `nil` ``ParsedScript/DisplayWord/matchIndex``).
    public var isMatchable: Bool

    public init(text: String, isMatchable: Bool = true) {
        self.text = text
        self.isMatchable = isMatchable
    }
}
