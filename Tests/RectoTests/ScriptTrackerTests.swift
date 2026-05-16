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
        #expect(tracker.currentWordIndex == 3)
    }

    @Test func `a 3-gram probe matches against the tail of a long transcript`() {
        let tracker = makeTracker()
        let preamble = String(repeating: "umm ", count: 40)
        tracker.consume(transcript: preamble + "the quick brown")
        #expect(tracker.currentWordIndex == 3)
    }

    // MARK: - Fallbacks

    @Test func `a 2-gram fallback advances when no 3-gram match is available`() {
        let tracker = makeTracker()
        tracker.consume(transcript: "quick brown")
        #expect(tracker.currentWordIndex == 3)
    }

    @Test func `a single-word fallback advances when the flag is enabled`() {
        let tracker = makeTracker()
        tracker.consume(transcript: "brown")
        #expect(tracker.currentWordIndex == 3)
    }

    @Test func `a single-word fallback is suppressed when the flag is disabled`() {
        let tracker = makeTracker(allowSingleWordFallback: false)
        tracker.consume(transcript: "brown")
        #expect(tracker.currentWordIndex == 0)
    }

    @Test func `the 2-gram fallback still runs when the single-word fallback is disabled`() {
        let tracker = makeTracker(allowSingleWordFallback: false)
        tracker.consume(transcript: "quick brown")
        #expect(tracker.currentWordIndex == 3)
    }

    // MARK: - Forward-only

    @Test func `the cursor does not move backwards when a later transcript drifts back`() {
        let tracker = makeTracker()
        tracker.consume(transcript: "fox jumps over")
        let advanced = tracker.currentWordIndex
        tracker.consume(transcript: "the quick brown")
        #expect(tracker.currentWordIndex == advanced)
    }

    @Test func `a negative offset never pulls the cursor back below its previous position`() {
        let tracker = makeTracker(offset: -5)
        tracker.setPosition(6)
        tracker.consume(transcript: "the lazy dog")
        #expect(tracker.currentWordIndex >= 6)
    }

    // MARK: - Stall

    @Test func `the cursor stays put when no probe matches in the window`() {
        let tracker = makeTracker()
        tracker.consume(transcript: "wibble wobble flibbertigibbet")
        #expect(tracker.currentWordIndex == 0)
    }

    @Test func `an empty transcript leaves the cursor untouched`() {
        let tracker = makeTracker()
        tracker.consume(transcript: "")
        #expect(tracker.currentWordIndex == 0)
    }

    // MARK: - Window boundaries

    @Test func `the cursor does not run past the end of the script`() {
        let tracker = makeTracker(lookAheadWindow: 20)
        tracker.consume(transcript: "runs away quickly")
        #expect(tracker.currentWordIndex == 13)
        tracker.consume(transcript: "runs away quickly")
        #expect(tracker.currentWordIndex == 13)
    }

    @Test func `matches outside the look-ahead window are ignored`() {
        let tracker = makeTracker(lookAheadWindow: 3)
        // "fox jumps over" lives at indices 3..5 — outside the [0, 3) window.
        tracker.consume(transcript: "fox jumps over")
        #expect(tracker.currentWordIndex == 0)
    }

    @Test func `widening the look-ahead window lets the matcher reach further ahead`() {
        let tracker = makeTracker(lookAheadWindow: 10)
        tracker.consume(transcript: "fox jumps over")
        #expect(tracker.currentWordIndex == 6)
    }

    // MARK: - Offset

    @Test func `a positive offset shifts the cursor further forward after a match`() {
        let tracker = makeTracker(offset: 1)
        tracker.consume(transcript: "the quick brown")
        #expect(tracker.currentWordIndex == 4)
    }

    @Test func `a negative offset shifts the cursor back from the match end`() {
        let tracker = makeTracker(offset: -1)
        tracker.consume(transcript: "the quick brown")
        #expect(tracker.currentWordIndex == 2)
    }

    @Test func `offset is clamped against the end of the script`() {
        let tracker = makeTracker(offset: 100, lookAheadWindow: 20)
        tracker.consume(transcript: "runs away quickly")
        #expect(tracker.currentWordIndex == 13)
    }

    // MARK: - Reset

    @Test func `reset returns the cursor to zero`() {
        let tracker = makeTracker()
        tracker.consume(transcript: "fox jumps over")
        #expect(tracker.currentWordIndex == 6)
        tracker.reset()
        #expect(tracker.currentWordIndex == 0)
    }

    // MARK: - setPosition

    @Test func `setPosition moves the cursor forward`() {
        let tracker = makeTracker()
        tracker.setPosition(5)
        #expect(tracker.currentWordIndex == 5)
    }

    @Test func `setPosition can move the cursor backwards`() {
        let tracker = makeTracker()
        tracker.consume(transcript: "the lazy dog")
        #expect(tracker.currentWordIndex == 9)
        tracker.setPosition(2)
        #expect(tracker.currentWordIndex == 2)
    }

    @Test func `setPosition clamps negative inputs to zero`() {
        let tracker = makeTracker()
        tracker.setPosition(-10)
        #expect(tracker.currentWordIndex == 0)
    }

    @Test func `setPosition clamps over-end inputs to the last valid index`() {
        let tracker = makeTracker()
        tracker.setPosition(9_999)
        #expect(tracker.currentWordIndex == 12)
    }

    @Test func `setPosition on an empty script leaves the cursor at zero`() {
        let tracker = makeTracker(text: "")
        tracker.setPosition(5)
        #expect(tracker.currentWordIndex == 0)
    }

    @Test func `setPosition is followed by consume resuming from the new index`() {
        let tracker = makeTracker()
        tracker.setPosition(6)
        tracker.consume(transcript: "the lazy dog")
        #expect(tracker.currentWordIndex == 9)
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
        #expect(tracker.currentWordIndex == 6)
    }

    @Test func `a revised transcript still advances rather than retreating`() {
        let tracker = makeTracker()
        tracker.consume(transcript: "the quick")
        let afterFirst = tracker.currentWordIndex
        // Simulate a recognition revision that re-emits earlier words.
        tracker.consume(transcript: "the quick brown fox")
        #expect(tracker.currentWordIndex > afterFirst)
    }
}
