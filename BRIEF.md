# Recto — package brief

A Swift Package providing the shared script-following engine used by
Quarto (macOS surtitle engine) and Octavo (iOS autocue app). Recto
contains the script model, the matcher, and the on-device speech
recognition service. It contains no UI, no persistence, and no
platform-specific capture pipeline.

## Naming

*Recto* is the right-hand page of an open book — the side a reader's eye
falls on first. The package sits underneath the page-format apps (Quarto,
Octavo) as the shared text they both rest on. The name is part of the
Strange Magic bibliographic family.

## Constraints

- **Platforms:** iOS 26.0, iPadOS 26.0, macOS 26.0 minimum.
- **Swift tools version:** 6.0+ (for Swift 6.2 strict concurrency).
- **Concurrency:** Strict Swift 6.2 concurrency. Use `async`/`await`,
  actors, and `AsyncStream`. No completion handlers, no Combine, no
  `DispatchQueue`.
- **Speech framework:** Use the new `SpeechAnalyzer` + `SpeechTranscriber`
  APIs introduced in iOS 26 / macOS 26. **Do not** use the older
  `SFSpeechRecognizer` recognition API. (The `SFSpeechRecognizer`
  *authorisation* API is fine to use — that hasn't been replaced.)
- **Dependencies:** None in v1. Pure `Foundation`, `Speech`, and
  `AVFoundation` (system frameworks only).
- **Style:** British English in comments and DocC. Public symbols use
  US-English spelling where it matches Apple convention (e.g. `Color`,
  `synchronize`) — Apple's own APIs use US spelling, so consistency
  with the platform wins over British preference at the API surface.

## Hosting

- Private GitHub repository: `StrangeMagic/Recto` (or similar).
- Distributed via Swift Package Manager with SSH or token-based access.
- Consuming apps reference by Git URL and tag-based version pin.
- During active co-development, apps may temporarily reference the
  package by local path; switch to a tagged version once API stabilises.

## Public API surface

Deliberately small. Five public types.

### `ParsedScript`

```swift
public struct ParsedScript: Sendable {
    public let title: String
    public let displayWords: [DisplayWord]
    public let normalisedWords: [String]

    public struct DisplayWord: Sendable, Identifiable {
        public let id: Int            // index into normalisedWords
        public let text: String       // original token, e.g. "today,"
        public let trailingSpace: Bool
        public let trailingNewline: Bool
    }
}
```

Value type, fully `Sendable`. Built via `ScriptParser` (below).

### `ScriptParser`

```swift
public enum ScriptParser {
    public static func parse(_ rawText: String, title: String = "")
        -> ParsedScript
}
```

Stateless parser. Tokenises on whitespace, preserving line breaks. For
each token, produces both a display form (preserved punctuation and
case) and a normalised form (lowercased, with leading/trailing
punctuation stripped — internal apostrophes preserved, e.g. `"don't"` →
`"don't"`).

### `ScriptTracker`

```swift
@MainActor @Observable
public final class ScriptTracker {
    public let script: ParsedScript
    public private(set) var currentWordIndex: Int = 0

    public var offset: Int
    public var lookAheadWindow: Int

    public init(
        script: ParsedScript,
        offset: Int = 0,
        lookAheadWindow: Int = 10
    )

    public func consume(transcript: String)
    public func setPosition(_ index: Int)
    public func reset()
}
```

The matcher. No internal defaults beyond `offset = 0, lookAheadWindow = 10`
— each consuming app passes its own preferred defaults at init time.

**Sendable behaviour:** `ScriptTracker` is deliberately *not*
`Sendable`. The `@MainActor` isolation means all access to the
tracker — including `consume(_:)`, `setPosition(_:)`, and reading
`currentWordIndex` — must happen on the main actor. Consumers
calling from non-main-actor contexts (such as a `Task` iterating an
`AsyncStream` of transcripts) must hop to the main actor explicitly:

```swift
Task {
    for await transcript in speechService.transcripts {
        await MainActor.run {
            tracker.consume(transcript: transcript)
        }
    }
}
```

This is the correct pattern. Do not attempt to make `ScriptTracker`
`Sendable`; the main-actor isolation is intentional and exists
because SwiftUI's `@Observable` system expects observation on the
main actor.

`setPosition(_:)` is the manual override mechanism. It clamps the
given index to `0 ..< script.normalisedWords.count` and sets
`currentWordIndex` directly, bypassing the forward-only rule. The next
`consume(transcript:)` call resumes matching from the new position.
Consuming apps use this for user-driven scrubbing (drag to scroll, tap
to jump) without losing voice-tracking continuity afterwards.

#### Matching algorithm

On each `consume(transcript:)` call:

1. Take the **tail** of the transcript (last 80 characters).
2. Normalise the tail the same way `ScriptParser` does.
3. Take the last **3 words** of the tail as the primary probe.
4. Search the look-ahead window
   (`script.normalisedWords[currentWordIndex ..<
   min(currentWordIndex + lookAheadWindow, script.normalisedWords.count)]`)
   for the probe sequence.
5. If found, advance `currentWordIndex` to the position *after* the last
   word of the match.
6. If not found, try a **2-word** probe in the same window.
7. If not found, try a **1-word** probe in the same window.
8. If still not found, do nothing — stay put.
9. **Never decrease `currentWordIndex` via matcher advances.**
   Forward-only for matcher-driven movement. Manual overrides via
   `setPosition(_:)` are explicitly exempt from this rule and may move
   the cursor in any direction.

The 1-word last-resort probe is configurable via a constructor flag in
case Quarto (where misfire cost is higher) wants to disable it:

```swift
public init(
    script: ParsedScript,
    offset: Int = 0,
    lookAheadWindow: Int = 10,
    allowSingleWordFallback: Bool = true
)
```

Defaults to `true`. Quarto passes `false`; Octavo passes `true`.

Internal constants:

```swift
private let tailCharacterCount = 80
private let primaryProbeLength = 3
private let fallbackProbeLength = 2
private let lastResortProbeLength = 1
```

These are deliberately not exposed publicly. They're a contract between
the package and its consumers based on empirical testing; if testing
shows they should change, the change should be a package update affecting
both apps.

### `SpeechService`

```swift
public actor SpeechService {
    public enum ModelState: Sendable, Equatable {
        case notReady
        case downloading(progress: Double)
        case ready
        case failed
    }

    public enum SpeechServiceError: Error, Sendable, Equatable {
        case unsupportedLocale(Locale)
        case modelDownloadFailed(underlying: String)
        case audioConversionFailed
        case analyserFailed(underlying: String)
        case notPrepared
    }

    public private(set) var modelState: ModelState = .notReady

    public nonisolated let transcripts: AsyncStream<String>
    public nonisolated let errors: AsyncStream<SpeechServiceError>

    public init(locale: Locale = Locale(identifier: "en-GB"))

    public func prepare() async throws
    public func consume(_ buffer: CMSampleBuffer) async
    public func reset() async
    public func finish() async
}
```

Owns the `SpeechAnalyzer` and `SpeechTranscriber`. Accepts
`CMSampleBuffer` audio input — matching Octavo's capture pipeline
natively. Quarto's `AVAudioEngine` tap produces `AVAudioPCMBuffer`s,
which it must convert to `CMSampleBuffer` before calling
`consume(_:)`. A conversion helper is exposed below.

**Responsibilities:**

- On `prepare()`, verify the requested locale is supported by
  `SpeechTranscriber`. If not, throw `.unsupportedLocale(Locale)`.
  This is the responsibility of the caller to handle — fall back to
  en-GB, surface an error to the user, or whatever fits the
  consuming app's UX.
- If the locale is supported but the model is not yet downloaded,
  trigger an `AssetInventory` download. Surface progress via
  `modelState` (`.downloading(progress:)` then `.ready`). If the
  download fails, transition to `.failed`, emit a
  `.modelDownloadFailed` to the `errors` stream, and throw.
- Configure `SpeechAnalyzer` with on-device recognition required (no
  server fallback under any circumstance).
- Feed incoming `CMSampleBuffer`s into the analyser's input sequence.
  If buffer conversion fails for a given buffer, emit
  `.audioConversionFailed` to the `errors` stream and drop that
  buffer — do not throw, do not terminate the service.
- Publish cumulative recognised text via the `transcripts` stream on
  every update.
- If the analyser itself fails mid-session (rare; format change,
  hardware change), transition `modelState` to `.failed`, emit an
  `.analyserFailed` error, and stop accepting buffers until
  `prepare()` is called again.

**Locale handling:**

The default locale is `en-GB`. Consumers may pass any locale they
like; `prepare()` is the validation point. Callers should treat
`.unsupportedLocale` as a soft error — they can choose to retry with
en-GB, prompt the user to install the requested language, or surface
a "language not supported" message. Recto's job is to be clear about
what's supported; the consuming app decides how to recover.

**Streams (`transcripts` and `errors`):**

Both streams are `AsyncStream`s, both `nonisolated let`. They're
intended to be consumed independently — `errors` is informational
and does not terminate `transcripts`. Errors that *do* terminate
recognition (analyser failure) are surfaced via `modelState` as well
as the errors stream, so consumers observing `modelState` will see
the transition to `.failed`.

The streams are stored as `nonisolated(unsafe)` continuations to be
writable from the buffer-consume path without blocking the actor.
This is the idiomatic Swift 6.2 pattern for actor-to-stream bridging.

**Lifetime:**

`SpeechService` is one-shot per session. The expected lifecycle is:

1. Init.
2. `prepare()`.
3. Many `consume(_:)` calls.
4. Optionally `reset()` (clears the analyser's accumulated transcript
   state but keeps the service usable; cheap).
5. `finish()` when done, or deinit.

**Explicit termination:** call `finish()` to terminate both streams,
release the analyser, and clean up resources. Subsequent
`consume(_:)` calls are no-ops; `prepare()` after `finish()` is
undefined (callers should construct a fresh service).

**Automatic termination:** if the service is deallocated without
`finish()` being called, both stream continuations are finished from
`deinit` as a safety net. This handles the case where SwiftUI tears
down a view that owns the service — the service deinits, the streams
end cleanly, and consuming `for await` loops exit.

Callers should prefer `finish()` for explicit control. The deinit
safety net exists to prevent stream consumers hanging in error cases,
not as the primary termination mechanism.

### `AudioBufferConverter`

```swift
public enum AudioBufferConverter {
    public static func sampleBuffer(
        from pcmBuffer: AVAudioPCMBuffer,
        presentationTime: CMTime
    ) throws -> CMSampleBuffer
}
```

A small helper for converting `AVAudioPCMBuffer` (the `AVAudioEngine`
output type) into `CMSampleBuffer` (Recto's `SpeechService` input type).
Used by Quarto's audio engine bridge. Octavo doesn't need it.

This lives in the package because both the source format and the target
format are platform types, and the conversion is the same on both
platforms.

## Internal structure

```
Recto/
├── Package.swift
├── README.md
├── Sources/
│   └── Recto/
│       ├── ParsedScript.swift
│       ├── ScriptParser.swift
│       ├── ScriptTracker.swift
│       ├── SpeechService.swift
│       └── AudioBufferConverter.swift
└── Tests/
    └── RectoTests/
        ├── ScriptParserTests.swift
        ├── ScriptTrackerTests.swift
        └── AudioBufferConverterTests.swift
```

`Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Recto",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Recto", targets: ["Recto"])
    ],
    targets: [
        .target(
            name: "Recto",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "RectoTests",
            dependencies: ["Recto"]
        )
    ]
)
```

## Tests

Unit tests are mandatory for the parser and tracker, since these are
pure logic with no platform dependencies. `SpeechService` and
`AudioBufferConverter` are harder to test in isolation — leave their
testing to integration tests in the consuming apps.

### `ScriptParserTests`

Cover:
- Plain prose tokenisation.
- Punctuation normalisation (`"Hello,"` → `"hello"`).
- Apostrophe preservation (`"don't"` → `"don't"`).
- Mixed case normalisation.
- Line breaks preserved in `trailingNewline`.
- Empty input.
- Single-word input.
- Long input (1000+ words) for performance smoke test.

### `ScriptTrackerTests`

Cover:
- Basic forward matching with a 3-gram probe.
- Fallback to 2-gram when 3-gram misses.
- Fallback to 1-gram when both miss (and `allowSingleWordFallback = true`).
- No fallback to 1-gram when `allowSingleWordFallback = false`.
- Forward-only: cursor never decreases when transcript drifts backwards.
- Stall behaviour: cursor stays put when no match in window.
- Window boundaries: cursor doesn't run off the end of the script.
- Configurable `offset` and `lookAheadWindow` (verify they're respected).
- Reset behaviour.
- `setPosition(_:)`: cursor moves to the given index, including backwards.
- `setPosition(_:)`: clamps to valid range (negative inputs → 0; over-end
  inputs → last valid index).
- `setPosition(_:)` followed by `consume(_:)`: matcher resumes from the
  new position; the look-ahead window opens from the manually-set index.

Use synthetic transcripts that simulate real recognition patterns —
growing strings with occasional revisions, not perfect inputs.

## Consumer integration

### Octavo (iOS, Octavo brief refers to this)

```swift
import Recto

// In CaptureService (Octavo-specific):
//   AVCaptureAudioDataOutput delegate produces CMSampleBuffer
//   ↓
//   await speechService.consume(buffer)

let speechService = SpeechService(locale: Locale(identifier: "en-GB"))

do {
    try await speechService.prepare()
} catch SpeechServiceError.unsupportedLocale {
    // Should not happen for en-GB on a UK-region device.
    // Octavo surfaces a clear error and offers to retry.
} catch {
    // Model download failure or similar; surface to user.
}

let parsedScript = ScriptParser.parse(script.rawText, title: script.title)
let tracker = ScriptTracker(
    script: parsedScript,
    offset: 1,
    lookAheadWindow: 10,
    allowSingleWordFallback: true
)

// Consume transcripts on the main actor.
Task {
    for await transcript in speechService.transcripts {
        await MainActor.run {
            tracker.consume(transcript: transcript)
        }
    }
}

// Observe errors independently. Octavo can log, show a non-blocking
// toast, or react however it likes — errors do not terminate the
// service.
Task {
    for await error in speechService.errors {
        // Log or surface to UI.
    }
}

// When the user dismisses the reader:
await speechService.finish()
```

### Quarto (macOS, Quarto brief refers to this)

```swift
import Recto
import AVFoundation

// Quarto owns an AVAudioEngine:
let speechService = SpeechService(locale: Locale(identifier: "en-GB"))
try await speechService.prepare()

let audioEngine = AVAudioEngine()
audioEngine.inputNode.installTap(
    onBus: 0,
    bufferSize: 1024,
    format: audioEngine.inputNode.outputFormat(forBus: 0)
) { pcmBuffer, time in
    Task {
        do {
            let sampleBuffer = try AudioBufferConverter.sampleBuffer(
                from: pcmBuffer,
                presentationTime: time.audioBufferPresentationTime
            )
            await speechService.consume(sampleBuffer)
        } catch {
            // Conversion failed; drop this buffer. Recto's
            // SpeechService also emits .audioConversionFailed if
            // it fails internally.
        }
    }
}

let parsedScript = ScriptParser.parse(script.rawText, title: script.title)
let tracker = ScriptTracker(
    script: parsedScript,
    offset: -1,
    lookAheadWindow: 8,
    allowSingleWordFallback: false   // Quarto wants stricter matching
)

// Same transcripts and errors pattern as Octavo.
// On shutdown:
await speechService.finish()
```

## Build order

1. `Package.swift` and empty target. Verify the package builds clean
   for both iOS 26 and macOS 26.
2. `ParsedScript` and `ScriptParser` with tests. Verify parser tests
   pass on both platforms.
3. `ScriptTracker` with tests. Verify the matcher logic with synthetic
   transcripts.
4. `SpeechService` actor. Integration-test by running it in a small
   sample iOS or macOS test harness.
5. `AudioBufferConverter`. Integration-test from a macOS sample using
   `AVAudioEngine`.
6. README with usage examples for both Octavo and Quarto.
7. Tag a `0.1.0` release and switch consuming apps from local-path to
   Git-URL references.

## Definition of done

- Package builds clean for iOS 26 and macOS 26 with no concurrency
  warnings.
- All parser and tracker tests pass.
- Octavo can `import Recto` and successfully drive its `ScriptTracker`
  from `CaptureService` audio buffers.
- Quarto can `import Recto` and successfully drive its `ScriptTracker`
  from `AVAudioEngine` audio buffers via `AudioBufferConverter`.
- Public API surface is documented with DocC comments on every public
  symbol.
- README in the repo explains the package, links to both consumer
  apps, and includes the integration snippets above.

## Notes for the implementer

- Resist the urge to add features. Recto's value comes from being
  small and stable. The matcher should not gain new probe strategies,
  ML models, fuzzy matching, or anything else without strong evidence
  from real usage.
- The matcher constants (3/2/1-gram, 80-char tail) are inherited from
  empirical testing on the Quarto sibling project. Don't change them
  without testing against both apps.
- The `nonisolated(unsafe)` continuations in `SpeechService` are the
  idiomatic Swift 6.2 pattern for bridging Sendable closures into
  actor-isolated state. Don't try to clean them up with safer
  wrappers — they're correct as-is.
- `AssetInventory` model downloads can take time on first launch.
  Consumer apps should show clear progress UI; the package surfaces
  progress but doesn't dictate presentation.
- The package has no opinion on UI, persistence, capture pipelines,
  or recording. That's deliberate. Keep it that way.
