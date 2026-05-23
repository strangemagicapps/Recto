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
/// `setPosition(matchIndex:)` is the manual override for user-driven scrubbing
/// (drag-to-scroll, tap-to-jump). It bypasses the forward-only rule and
/// clamps to the script's valid range.
///
/// ## Concurrency
///
/// `ScriptTracker` is `@MainActor`-isolated and deliberately *not*
/// `Sendable`. SwiftUI's observation system expects `@Observable` state
/// to be touched on the main actor, so every property read,
/// ``consume(transcript:)`` call, and `setPosition` call must
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
    /// matchable word the tracker expects to encounter. Starts at `0`.
    ///
    /// Updated by ``consume(transcript:)`` (forward-only) and by
    /// ``setPosition(matchIndex:)`` (any direction). This indexes the *matchable*
    /// sequence, which omits display-only tokens, so it cannot be used to
    /// index ``ParsedScript/displayWords`` directly — use
    /// ``currentDisplayIndex`` to locate the cursor in the displayed
    /// script.
    public private(set) var currentMatchIndex: Int = 0

    /// The index, into ``ParsedScript/normalisedWords``, of the next word
    /// the tracker expects to encounter.
    ///
    /// - Important: This name predates the split between the displayed and
    ///   matchable token sequences and misleadingly implies a position in
    ///   the displayed script. Use ``currentMatchIndex`` for the matcher
    ///   position, or ``currentDisplayIndex`` to locate the cursor in
    ///   ``ParsedScript/displayWords``.
    @available(*, deprecated, renamed: "currentMatchIndex", message: "Use currentMatchIndex for the matcher position, or currentDisplayIndex to index displayWords.")
    public var currentWordIndex: Int { currentMatchIndex }

    /// The position in ``ParsedScript/displayWords`` that renders the word
    /// at ``currentMatchIndex``, or `nil` when the cursor is parked one
    /// past the final word.
    ///
    /// This is the convenient hook for a UI: ``currentMatchIndex`` indexes
    /// the matchable ``ParsedScript/normalisedWords``, which omits
    /// display-only tokens, so it cannot be used to index the displayed
    /// script directly. This property performs the O(1) translation via
    /// ``ParsedScript/displayIndex(forMatchIndex:)``.
    public var currentDisplayIndex: Int? {
        script.displayIndex(forMatchIndex: currentMatchIndex)
    }

    /// A signed shift applied to the cursor after each successful match.
    ///
    /// With `offset = 0` (the default) the cursor lands on the index
    /// immediately *after* the last matched word — i.e. the next word
    /// expected. Positive values push the cursor further ahead; negative
    /// values pull it back towards the matched run. Forward-only still
    /// applies: a negative offset will never reduce ``currentMatchIndex``.
    public var offset: Int

    /// The number of normalised words ahead of ``currentMatchIndex`` that
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
    ///   - offset: Shift applied to ``currentMatchIndex`` after each
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
    /// This method is intended to be driven from
    /// ``SpeechService/transcripts``; each value yielded by that stream
    /// can be passed in unchanged.
    ///
    /// - Parameter transcript: The cumulative recognised text so far.
    public func consume(transcript: String) {
        let words = script.normalisedWords
        guard currentMatchIndex < words.count else { return }

        let tail = String(transcript.suffix(Self.tailCharacterCount))
        let probeWords = ScriptParser.parse(tail)
            .normalisedWords
            .filter { !$0.isEmpty }
        guard !probeWords.isEmpty else { return }

        let windowEnd = min(currentMatchIndex + lookAheadWindow, words.count)
        guard currentMatchIndex < windowEnd else { return }

        let probeLengths: [Int] = allowSingleWordFallback
            ? [Self.primaryProbeLength, Self.fallbackProbeLength, Self.lastResortProbeLength]
            : [Self.primaryProbeLength, Self.fallbackProbeLength]

        for length in probeLengths {
            guard probeWords.count >= length else { continue }
            let probe = probeWords.suffix(length)
            guard let matchStart = words[currentMatchIndex ..< windowEnd]
                .firstRange(of: probe)?.lowerBound
            else { continue }

            let matchEnd = matchStart + length
            let proposed = matchEnd + offset
            let clamped = min(max(proposed, 0), words.count)
            if clamped > currentMatchIndex {
                currentMatchIndex = clamped
            }
            return
        }
    }

    /// How a ``ScriptTracker/setPosition(displayIndex:snapDirection:)`` call
    /// resolves a tap that lands on a display-only token — one with no
    /// spoken counterpart, such as a speaker name or stage direction.
    public enum SnapDirection: Sendable {
        /// Snap to the nearest spoken word at or after the tapped token,
        /// falling back to the nearest spoken word before it when none
        /// lies ahead.
        case forward
        /// Snap to the nearest spoken word at or before the tapped token,
        /// falling back to the nearest spoken word after it when none
        /// lies behind.
        case backward
        /// Leave the cursor where it is; perform no movement.
        case reject
    }

    /// Moves the cursor to `matchIndex`, clamped to the script's valid
    /// range.
    ///
    /// Negative inputs clamp to `0`; inputs at or beyond the end of the
    /// script clamp to the last valid index. Unlike matcher-driven
    /// movement, this method may move the cursor in any direction; the
    /// next ``consume(transcript:)`` call resumes from the new position.
    ///
    /// - Parameter matchIndex: The target index in
    ///   ``ParsedScript/normalisedWords`` (the matchable sequence). To jump
    ///   from a tapped displayed word instead, use
    ///   ``setPosition(displayIndex:snapDirection:)``.
    public func setPosition(matchIndex: Int) {
        let count = script.normalisedWords.count
        guard count > 0 else {
            currentMatchIndex = 0
            return
        }
        currentMatchIndex = min(max(matchIndex, 0), count - 1)
    }

    /// Moves the cursor to `index`, clamped to the script's valid range.
    ///
    /// - Parameter index: The target index in
    ///   ``ParsedScript/normalisedWords``.
    @available(*, deprecated, renamed: "setPosition(matchIndex:)", message: "The unlabelled index is a normalisedWords (match) index; use setPosition(matchIndex:), or setPosition(displayIndex:snapDirection:) to jump from a displayed word.")
    public func setPosition(_ index: Int) {
        setPosition(matchIndex: index)
    }

    /// Moves the cursor from a position in ``ParsedScript/displayWords``,
    /// the displayed token sequence used by user-driven scrubbing
    /// (drag-to-scroll, tap-to-jump).
    ///
    /// When the tapped word is spoken (its ``ParsedScript/DisplayWord/matchIndex``
    /// is non-`nil`) the cursor moves to that word. When it is display-only
    /// — a speaker name, stage direction, or scene heading with no spoken
    /// counterpart — `snapDirection` decides how to resolve the tap. Like
    /// ``setPosition(matchIndex:)``, this bypasses the forward-only rule and
    /// may move the cursor in any direction.
    ///
    /// - Parameters:
    ///   - displayIndex: The target position in
    ///     ``ParsedScript/displayWords``. Clamped to the valid range.
    ///   - snapDirection: How to resolve a tap on a display-only token.
    ///     Defaults to ``SnapDirection/forward``.
    public func setPosition(displayIndex: Int, snapDirection: SnapDirection = .forward) {
        let display = script.displayWords
        guard !display.isEmpty else {
            currentMatchIndex = 0
            return
        }
        let clamped = min(max(displayIndex, 0), display.count - 1)

        // A spoken word resolves directly, regardless of snap direction.
        if let matchIndex = display[clamped].matchIndex {
            setPosition(matchIndex: matchIndex)
            return
        }

        let ahead = display[clamped...].lazy.compactMap(\.matchIndex).first
        let behind = display[...clamped].reversed().lazy.compactMap(\.matchIndex).first

        let target: Int?
        switch snapDirection {
        case .forward: target = ahead ?? behind
        case .backward: target = behind ?? ahead
        case .reject: target = nil
        }
        if let target { setPosition(matchIndex: target) }
    }

    /// Resets the cursor to the beginning of the script.
    public func reset() {
        currentMatchIndex = 0
    }
}
