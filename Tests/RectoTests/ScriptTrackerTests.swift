import Testing
@testable import Recto

@MainActor
@Suite("ScriptTracker")
struct ScriptTrackerTests {
    private static let prose =
        "the quick brown fox jumps over the lazy dog and runs away quickly"

    private func makeTracker(
        offset: Int = 0,
        lookAheadWindow: Int = 10,
        allowSingleWordFallback: Bool = true,
        text: String = ScriptTrackerTests.prose
    ) -> ScriptTracker {
        ScriptTracker(
            script: ScriptParser.parse(text),
            offset: offset,
            lookAheadWindow: lookAheadWindow,
            allowSingleWordFallback: allowSingleWordFallback
        )
    }

    // MARK: - Primary probe

    @Test func `a 3-gram probe advances the cursor past the matched run`() {
        let tracker = makeTracker()
        tracker.consume(transcript: "the quick brown")
        #expect(tracker.currentMatchIndex == 3)
    }

    @Test func `a 3-gram probe matches against the tail of a long transcript`() {
        let tracker = makeTracker()
        let preamble = String(repeating: "umm ", count: 40)
        tracker.consume(transcript: preamble + "the quick brown")
        #expect(tracker.currentMatchIndex == 3)
    }

    // MARK: - Fallbacks

    @Test func `a 2-gram fallback advances when no 3-gram match is available`() {
        let tracker = makeTracker()
        tracker.consume(transcript: "quick brown")
        #expect(tracker.currentMatchIndex == 3)
    }

    @Test func `a single-word fallback advances when the flag is enabled`() {
        let tracker = makeTracker()
        tracker.consume(transcript: "brown")
        #expect(tracker.currentMatchIndex == 3)
    }

    @Test func `a single-word fallback is suppressed when the flag is disabled`() {
        let tracker = makeTracker(allowSingleWordFallback: false)
        tracker.consume(transcript: "brown")
        #expect(tracker.currentMatchIndex == 0)
    }

    @Test func `the 2-gram fallback still runs when the single-word fallback is disabled`() {
        let tracker = makeTracker(allowSingleWordFallback: false)
        tracker.consume(transcript: "quick brown")
        #expect(tracker.currentMatchIndex == 3)
    }

    // MARK: - Forward-only

    @Test func `the cursor does not move backwards when a later transcript drifts back`() {
        let tracker = makeTracker()
        tracker.consume(transcript: "fox jumps over")
        let advanced = tracker.currentMatchIndex
        tracker.consume(transcript: "the quick brown")
        #expect(tracker.currentMatchIndex == advanced)
    }

    @Test func `a negative offset never pulls the cursor back below its previous position`() {
        let tracker = makeTracker(offset: -5)
        tracker.setPosition(matchIndex:6)
        tracker.consume(transcript: "the lazy dog")
        #expect(tracker.currentMatchIndex >= 6)
    }

    // MARK: - Stall

    @Test func `the cursor stays put when no probe matches in the window`() {
        let tracker = makeTracker()
        tracker.consume(transcript: "wibble wobble flibbertigibbet")
        #expect(tracker.currentMatchIndex == 0)
    }

    @Test func `an empty transcript leaves the cursor untouched`() {
        let tracker = makeTracker()
        tracker.consume(transcript: "")
        #expect(tracker.currentMatchIndex == 0)
    }

    // MARK: - Window boundaries

    @Test func `the cursor does not run past the end of the script`() {
        let tracker = makeTracker(lookAheadWindow: 20)
        tracker.consume(transcript: "runs away quickly")
        #expect(tracker.currentMatchIndex == 13)
        tracker.consume(transcript: "runs away quickly")
        #expect(tracker.currentMatchIndex == 13)
    }

    @Test func `matches outside the look-ahead window are ignored`() {
        let tracker = makeTracker(lookAheadWindow: 3)
        // "fox jumps over" lives at indices 3..5 — outside the [0, 3) window.
        tracker.consume(transcript: "fox jumps over")
        #expect(tracker.currentMatchIndex == 0)
    }

    @Test func `widening the look-ahead window lets the matcher reach further ahead`() {
        let tracker = makeTracker(lookAheadWindow: 10)
        tracker.consume(transcript: "fox jumps over")
        #expect(tracker.currentMatchIndex == 6)
    }

    // MARK: - Offset

    @Test func `a positive offset shifts the cursor further forward after a match`() {
        let tracker = makeTracker(offset: 1)
        tracker.consume(transcript: "the quick brown")
        #expect(tracker.currentMatchIndex == 4)
    }

    @Test func `a negative offset shifts the cursor back from the match end`() {
        let tracker = makeTracker(offset: -1)
        tracker.consume(transcript: "the quick brown")
        #expect(tracker.currentMatchIndex == 2)
    }

    @Test func `offset is clamped against the end of the script`() {
        let tracker = makeTracker(offset: 100, lookAheadWindow: 20)
        tracker.consume(transcript: "runs away quickly")
        #expect(tracker.currentMatchIndex == 13)
    }

    // MARK: - Reset

    @Test func `reset returns the cursor to zero`() {
        let tracker = makeTracker()
        tracker.consume(transcript: "fox jumps over")
        #expect(tracker.currentMatchIndex == 6)
        tracker.reset()
        #expect(tracker.currentMatchIndex == 0)
    }

    // MARK: - setPosition

    @Test func `setPosition moves the cursor forward`() {
        let tracker = makeTracker()
        tracker.setPosition(matchIndex:5)
        #expect(tracker.currentMatchIndex == 5)
    }

    @Test func `setPosition can move the cursor backwards`() {
        let tracker = makeTracker()
        tracker.consume(transcript: "the lazy dog")
        #expect(tracker.currentMatchIndex == 9)
        tracker.setPosition(matchIndex:2)
        #expect(tracker.currentMatchIndex == 2)
    }

    @Test func `setPosition clamps negative inputs to zero`() {
        let tracker = makeTracker()
        tracker.setPosition(matchIndex:-10)
        #expect(tracker.currentMatchIndex == 0)
    }

    @Test func `setPosition clamps over-end inputs to the last valid index`() {
        let tracker = makeTracker()
        tracker.setPosition(matchIndex:9_999)
        #expect(tracker.currentMatchIndex == 12)
    }

    @Test func `setPosition on an empty script leaves the cursor at zero`() {
        let tracker = makeTracker(text: "")
        tracker.setPosition(matchIndex:5)
        #expect(tracker.currentMatchIndex == 0)
    }

    @Test func `setPosition is followed by consume resuming from the new index`() {
        let tracker = makeTracker()
        tracker.setPosition(matchIndex:6)
        tracker.consume(transcript: "the lazy dog")
        #expect(tracker.currentMatchIndex == 9)
    }

    // MARK: - Realistic growing transcripts

    @Test func `a growing transcript advances the cursor step by step`() {
        let tracker = makeTracker()
        let updates = [
            "the",
            "the quick",
            "the quick brown",
            "the quick brown fox",
            "the quick brown fox jumps",
            "the quick brown fox jumps over",
        ]
        for transcript in updates {
            tracker.consume(transcript: transcript)
        }
        #expect(tracker.currentMatchIndex == 6)
    }

    @Test func `a revised transcript still advances rather than retreating`() {
        let tracker = makeTracker()
        tracker.consume(transcript: "the quick")
        let afterFirst = tracker.currentMatchIndex
        // Simulate a recognition revision that re-emits earlier words.
        tracker.consume(transcript: "the quick brown fox")
        #expect(tracker.currentMatchIndex > afterFirst)
    }

    // MARK: - Display-only tokens

    /// Builds a script from `(text, matchable)` pairs. Matchable tokens are
    /// lowercased into `normalisedWords` and carry their match index;
    /// display-only tokens (speaker names, stage directions) get a `nil`
    /// match index and no normalised entry. Mirrors what a future Fountain
    /// frontend would emit, exercising the decoupled display/match arrays.
    private func makeMixedScript(_ tokens: [(text: String, matchable: Bool)]) -> ParsedScript {
        var displayWords: [ParsedScript.DisplayWord] = []
        var normalisedWords: [String] = []
        for (offset, token) in tokens.enumerated() {
            let matchIndex: Int?
            if token.matchable {
                matchIndex = normalisedWords.count
                normalisedWords.append(token.text.lowercased())
            } else {
                matchIndex = nil
            }
            displayWords.append(
                ParsedScript.DisplayWord(
                    id: offset,
                    matchIndex: matchIndex,
                    text: token.text,
                    trailingSpace: offset < tokens.count - 1,
                    trailingNewline: false
                )
            )
        }
        return ParsedScript(
            title: "",
            displayWords: displayWords,
            normalisedWords: normalisedWords
        )
    }

    // "ROMEO" and "(aside)" are display-only; the rest are spoken. The
    // spoken words occupy normalisedWords indices 0...7.
    private func makeMixedTracker() -> ScriptTracker {
        let script = makeMixedScript([
            ("ROMEO", false),
            ("But", true), ("soft", true), ("what", true),
            ("(aside)", false),
            ("light", true), ("through", true), ("yonder", true),
            ("window", true), ("breaks", true),
        ])
        return ScriptTracker(script: script)
    }

    @Test func `display-only tokens are absent from the normalised words`() {
        let tracker = makeMixedTracker()
        #expect(tracker.script.normalisedWords ==
            ["but", "soft", "what", "light", "through", "yonder", "window", "breaks"])
    }

    @Test func `the matcher advances over a display-only gap without stalling`() {
        let tracker = makeMixedTracker()
        // A spoken run that straddles the "(aside)" display-only token.
        tracker.consume(transcript: "soft what light")
        #expect(tracker.currentMatchIndex == 4)
        tracker.consume(transcript: "yonder window breaks")
        #expect(tracker.currentMatchIndex == 8)
    }

    @Test func `currentDisplayIndex lands past display-only tokens between spoken words`() {
        let tracker = makeMixedTracker()
        tracker.consume(transcript: "but soft what")
        // Cursor sits on normalised index 3 ("light"), whose display
        // position is 5 — after "ROMEO" (0) and the "(aside)" token (4).
        #expect(tracker.currentMatchIndex == 3)
        #expect(tracker.currentDisplayIndex == 5)
    }

    @Test func `currentDisplayIndex is nil when the cursor parks past the final word`() {
        let tracker = makeMixedTracker()
        tracker.consume(transcript: "yonder window breaks")
        #expect(tracker.currentMatchIndex == 8)
        #expect(tracker.currentDisplayIndex == nil)
    }

    @Test func `an all-display-only script leaves the matcher at zero and never crashes`() {
        let script = makeMixedScript([
            ("ROMEO", false),
            ("(enter, stage left)", false),
            ("ACT ONE", false),
        ])
        let tracker = ScriptTracker(script: script)
        tracker.consume(transcript: "romeo enter act one")
        #expect(tracker.currentMatchIndex == 0)
        #expect(tracker.currentDisplayIndex == nil)
    }

    // MARK: - setPosition(displayIndex:snapDirection:)

    @Test func `tapping a spoken display word moves to its match index`() {
        let tracker = makeMixedTracker()
        // "light" sits at display position 5, match index 3.
        tracker.setPosition(displayIndex: 5)
        #expect(tracker.currentMatchIndex == 3)
    }

    @Test func `forward snap from a display-only token lands on the next spoken word`() {
        let tracker = makeMixedTracker()
        // "(aside)" is display position 4; the next spoken word is "light" (3).
        tracker.setPosition(displayIndex: 4, snapDirection: .forward)
        #expect(tracker.currentMatchIndex == 3)
    }

    @Test func `backward snap from a display-only token lands on the previous spoken word`() {
        let tracker = makeMixedTracker()
        // "(aside)" is display position 4; the previous spoken word is "what" (2).
        tracker.setPosition(displayIndex: 4, snapDirection: .backward)
        #expect(tracker.currentMatchIndex == 2)
    }

    @Test func `reject snap on a display-only token leaves the cursor untouched`() {
        let tracker = makeMixedTracker()
        tracker.setPosition(matchIndex: 5)
        tracker.setPosition(displayIndex: 4, snapDirection: .reject)
        #expect(tracker.currentMatchIndex == 5)
    }

    @Test func `reject snap still moves when the tapped display word is spoken`() {
        let tracker = makeMixedTracker()
        // "light" (display 5) is spoken, so .reject still resolves it.
        tracker.setPosition(displayIndex: 5, snapDirection: .reject)
        #expect(tracker.currentMatchIndex == 3)
    }

    @Test func `forward snap falls back to the previous spoken word when none lies ahead`() {
        let tracker = ScriptTracker(
            script: makeMixedScript([("hello", true), ("(curtain)", false)])
        )
        tracker.setPosition(displayIndex: 1, snapDirection: .forward)
        #expect(tracker.currentMatchIndex == 0)
    }

    @Test func `setPosition by display index clamps an over-end input`() {
        let tracker = makeMixedTracker()
        // "breaks" is the final display word (position 9, match index 7).
        tracker.setPosition(displayIndex: 9_999)
        #expect(tracker.currentMatchIndex == 7)
    }

    @Test func `setPosition by display index on an empty script stays at zero`() {
        let tracker = makeTracker(text: "")
        tracker.setPosition(displayIndex: 3)
        #expect(tracker.currentMatchIndex == 0)
    }
}
