import Testing
@testable import Recto

@Suite("SpeechService transcript window")
struct SpeechServiceTranscriptWindowTests {

    /// Roughly the length of a spoken word plus its space.
    private func words(_ count: Int, prefix: String = "word") -> String {
        (0..<count).map { "\(prefix)\($0)" }.joined(separator: " ")
    }

    @Test func `text shorter than the window is left exactly as it is`() {
        let short = "the quick brown fox jumps over the lazy dog"
        #expect(SpeechService.trimmedToWindow(short) == short)
    }

    @Test func `a long transcript is bounded to the window`() {
        let long = words(4_000)
        #expect(long.count > SpeechService.retainedCharacterCount * 5)

        let trimmed = SpeechService.trimmedToWindow(long)
        #expect(trimmed.count <= SpeechService.retainedCharacterCount)
    }

    @Test func `trimming keeps the newest words and drops only the head`() {
        let long = words(4_000)
        let trimmed = SpeechService.trimmedToWindow(long)

        #expect(long.hasSuffix(trimmed), "the window is a suffix of what was said")
        #expect(trimmed.hasSuffix("word3999"), "the newest words survive")
        #expect(trimmed.hasPrefix("word0") == false, "the oldest do not")
    }

    @Test func `the window never opens mid-word`() {
        // A half word at the head would become a bogus probe for whatever is
        // matching against the transcript.
        let trimmed = SpeechService.trimmedToWindow(words(4_000))
        let firstWord = trimmed.prefix { $0 != " " }
        #expect(firstWord.hasPrefix("word"), "got a partial token: \(firstWord)")
    }

    @Test func `what the matcher actually reads is unchanged by trimming`() {
        // The guarantee that makes this safe: ScriptTracker probes the last 80
        // characters, so the window has to leave that stretch untouched.
        let long = words(4_000)
        let trimmed = SpeechService.trimmedToWindow(long)
        #expect(trimmed.suffix(80) == long.suffix(80))
    }

    @Test func `trimming is stable once inside the window`() {
        let once = SpeechService.trimmedToWindow(words(4_000))
        #expect(SpeechService.trimmedToWindow(once) == once)
    }

    @Test func `one unbroken token longer than the window survives`() {
        // No space to cut at. Returning "" here would silently stop matching.
        let unbroken = String(repeating: "a", count: SpeechService.retainedCharacterCount * 2)
        let trimmed = SpeechService.trimmedToWindow(unbroken)
        #expect(trimmed.count == SpeechService.retainedCharacterCount)
        #expect(trimmed.isEmpty == false)
    }

    @Test func `an empty transcript stays empty`() {
        #expect(SpeechService.trimmedToWindow("") == "")
    }
}
