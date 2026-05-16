import Foundation
import Observation

/// An observable cursor that advances through a ``ParsedScript`` as
/// recognised speech transcripts arrive.
///
/// `ScriptTracker` is the matching engine consumed by Quarto and Octavo.
/// On each ``consume(transcript:)`` call it inspects the tail of the
/// transcript, normalises it the same way ``ScriptParser`` does, and
/// searches a sliding look-ahead window of the script for the most
/// recent few words. When a match is found the cursor advances; when no
/// match is found the cursor stays put. Matcher-driven movement is
/// strictly forward-only — backwards drift in the transcript never
/// pulls the cursor backwards.
///
/// `setPosition(_:)` is the manual override for user-driven scrubbing
/// (drag-to-scroll, tap-to-jump). It bypasses the forward-only rule and
/// clamps to the script's valid range.
///
/// ## Concurrency
///
/// `ScriptTracker` is `@MainActor`-isolated and deliberately *not*
/// `Sendable`. SwiftUI's observation system expects `@Observable` state
/// to be touched on the main actor, so every property read,
/// ``consume(transcript:)`` call, and ``setPosition(_:)`` call must
/// happen on the main actor:
///
/// ```swift
/// Task {
///     for await transcript in speechService.transcripts {
///         await MainActor.run {
///             tracker.consume(transcript: transcript)
///         }
///     }
/// }
/// ```
@MainActor
@Observable
public final class ScriptTracker {
    /// The script the tracker is following. Set once at initialisation.
    public let script: ParsedScript

    /// The index, into ``ParsedScript/normalisedWords``, of the next
    /// word the tracker expects to encounter. Starts at `0`.
    ///
    /// Updated by ``consume(transcript:)`` (forward-only) and by
    /// ``setPosition(_:)`` (any direction). Reading this is the canonical
    /// way for a UI to know where the speaker is in the script.
    public private(set) var currentWordIndex: Int = 0

    /// A signed shift applied to the cursor after each successful match.
    ///
    /// With `offset = 0` (the default) the cursor lands on the index
    /// immediately *after* the last matched word — i.e. the next word
    /// expected. Positive values push the cursor further ahead; negative
    /// values pull it back towards the matched run. Forward-only still
    /// applies: a negative offset will never reduce ``currentWordIndex``.
    public var offset: Int

    /// The number of normalised words ahead of ``currentWordIndex`` that
    /// the matcher considers when searching for a probe. Wider windows
    /// are more forgiving of skipped or paraphrased text but cost more
    /// false matches.
    public var lookAheadWindow: Int

    /// When `true`, the matcher falls back to a single-word probe if
    /// neither the 3-word nor the 2-word probe finds a match in the
    /// window. Quarto sets this to `false` because misfires are costly
    /// for live surtitles; Octavo sets it to `true` to keep the autocue
    /// moving when recognition is patchy.
    public let allowSingleWordFallback: Bool

    private static let tailCharacterCount = 80
    private static let primaryProbeLength = 3
    private static let fallbackProbeLength = 2
    private static let lastResortProbeLength = 1

    /// Creates a tracker for `script`.
    ///
    /// - Parameters:
    ///   - script: The parsed script to follow.
    ///   - offset: Shift applied to ``currentWordIndex`` after each
    ///     successful match. Defaults to `0`.
    ///   - lookAheadWindow: How many words ahead of the cursor the
    ///     matcher searches on each ``consume(transcript:)`` call.
    ///     Defaults to `10`.
    ///   - allowSingleWordFallback: Whether to permit a one-word
    ///     last-resort probe. Defaults to `true`.
    public init(
        script: ParsedScript,
        offset: Int = 0,
        lookAheadWindow: Int = 10,
        allowSingleWordFallback: Bool = true
    ) {
        self.script = script
        self.offset = offset
        self.lookAheadWindow = lookAheadWindow
        self.allowSingleWordFallback = allowSingleWordFallback
    }

    /// Consumes the latest cumulative transcript and advances the cursor
    /// if a probe matches.
    ///
    /// The tracker looks only at the last 80 characters of `transcript`,
    /// so callers may pass the full growing transcript on every update
    /// without worrying about cost. Matcher-driven movement is
    /// forward-only: a transcript whose tail matches earlier in the
    /// script than the current cursor never moves the cursor backwards.
    ///
    /// - Parameter transcript: The cumulative recognised text so far.
    public func consume(transcript: String) {
        let words = script.normalisedWords
        guard currentWordIndex < words.count else { return }

        let tail = String(transcript.suffix(Self.tailCharacterCount))
        let probeWords = ScriptParser.parse(tail)
            .normalisedWords
            .filter { !$0.isEmpty }
        guard !probeWords.isEmpty else { return }

        let windowEnd = min(currentWordIndex + lookAheadWindow, words.count)
        guard currentWordIndex < windowEnd else { return }

        let probeLengths: [Int] = allowSingleWordFallback
            ? [Self.primaryProbeLength, Self.fallbackProbeLength, Self.lastResortProbeLength]
            : [Self.primaryProbeLength, Self.fallbackProbeLength]

        for length in probeLengths {
            guard probeWords.count >= length else { continue }
            let probe = probeWords.suffix(length)
            guard let matchStart = words[currentWordIndex ..< windowEnd]
                .firstRange(of: probe)?.lowerBound
            else { continue }

            let matchEnd = matchStart + length
            let proposed = matchEnd + offset
            let clamped = min(max(proposed, 0), words.count)
            if clamped > currentWordIndex {
                currentWordIndex = clamped
            }
            return
        }
    }

    /// Moves the cursor to `index`, clamped to the script's valid range.
    ///
    /// Negative inputs clamp to `0`; inputs at or beyond the end of the
    /// script clamp to the last valid index. Unlike matcher-driven
    /// movement, this method may move the cursor in any direction; the
    /// next ``consume(transcript:)`` call resumes from the new position.
    ///
    /// - Parameter index: The target index in
    ///   ``ParsedScript/normalisedWords``.
    public func setPosition(_ index: Int) {
        let count = script.normalisedWords.count
        guard count > 0 else {
            currentWordIndex = 0
            return
        }
        currentWordIndex = min(max(index, 0), count - 1)
    }

    /// Resets the cursor to the beginning of the script.
    public func reset() {
        currentWordIndex = 0
    }
}
