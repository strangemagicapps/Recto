# Recto

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fstrangemagicapps%2FRecto%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/strangemagicapps/Recto) [![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fstrangemagicapps%2FRecto%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/strangemagicapps/Recto)

A Swift package providing the shared script-following engine used by
**Quarto** (macOS surtitle engine) and **Lilt** (iOS autocue app).
Recto contains the script model, the matcher, and the on-device speech
recognition service. It contains no UI, no persistence, and no
platform-specific capture pipeline.

*Recto* is the right-hand page of an open book — the side a reader's eye
falls on first. The name is part of the Strange Magic bibliographic family
that is currently under development.

## Documentation

The full API reference — including the matcher algorithm and design
rationale — is published as DocC documentation at
**[strangemagicapps.github.io/Recto](https://strangemagicapps.github.io/Recto/documentation/recto)**.
It is rebuilt and deployed automatically on each release.

## Requirements

- iOS 26.0+ / iPadOS 26.0+ / macOS 26.0+ / tvOS 26.0+ / visionOS 26.0+
- Swift 6.3 toolchain (Xcode 26)
- Swift 6 language mode (strict concurrency, main-actor-by-default isolation)
- System frameworks only: `Foundation`, `Speech`, `AVFoundation`

Recto uses the new `SpeechAnalyzer` + `SpeechTranscriber` APIs introduced
in iOS 26, macOS 26 and associated OSs. It does **not** use the older
`SFSpeechRecognizer` recognition API.

## Installation

Add Recto to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/strangemagicapps/Recto.git", from: "0.1.0"),
],
targets: [
    .target(name: "MyApp", dependencies: ["Recto"]),
]
```

During active co-development, consuming apps may reference the package
by local path; switch to a tagged version once the API stabilises.

## Public API

Five public types — deliberately small.

| Type | Role |
| --- | --- |
| `ParsedScript` | `Sendable` value type holding tokenised script data. |
| `ScriptParser` | Stateless parser that produces a `ParsedScript`. |
| `ScriptTracker` | `@MainActor @Observable` matcher; advances a cursor through the script as transcripts arrive. |
| `SpeechService` | Actor wrapping `SpeechAnalyzer` + `SpeechTranscriber`; consumes `CMSampleBuffer`s, emits transcripts and errors via `AsyncStream`. |
| `AudioBufferConverter` | Helper for converting `AVAudioPCMBuffer` to `CMSampleBuffer`. |

See the [published DocC documentation](https://strangemagicapps.github.io/Recto/documentation/recto)
for the full API reference, matcher algorithm, and design rationale.

## Usage

### iOS, `CMSampleBuffer` capture

```swift
import Recto

let speechService = SpeechService(locale: Locale(identifier: "en-GB"))
try await speechService.prepare()

let parsedScript = ScriptParser.parse(script.rawText, title: script.title)
let tracker = ScriptTracker(
    script: parsedScript,
    offset: 1,
    lookAheadWindow: 10,
    allowSingleWordFallback: true
)

Task {
    for await transcript in speechService.transcripts {
        await MainActor.run {
            tracker.consume(transcript: transcript)
        }
    }
}

Task {
    for await error in speechService.errors {
        // Log or surface to UI; errors do not terminate the service.
    }
}

// Feed buffers from your capture pipeline:
await speechService.consume(sampleBuffer)

// On shutdown:
await speechService.finish()
```

### macOS, `AVAudioEngine` capture

```swift
import Recto
import AVFoundation

let speechService = SpeechService(locale: Locale(identifier: "en-GB"))
try await speechService.prepare()

let audioEngine = AVAudioEngine()
audioEngine.inputNode.installTap(
    onBus: 0,
    bufferSize: 1024,
    format: audioEngine.inputNode.outputFormat(forBus: 0)
) { pcmBuffer, time in
    Task {
        let sampleBuffer = try AudioBufferConverter.sampleBuffer(
            from: pcmBuffer,
            presentationTime: time.audioBufferPresentationTime
        )
        await speechService.consume(sampleBuffer)
    }
}

let tracker = ScriptTracker(
    script: ScriptParser.parse(script.rawText, title: script.title),
    offset: -1,
    lookAheadWindow: 8,
    allowSingleWordFallback: false   // Stricter matching for surtitles.
)
```

## Concurrency

- `ParsedScript` is `Sendable`.
- `ScriptTracker` is `@MainActor`-isolated and deliberately **not**
  `Sendable`. Consumers calling from non-main contexts must hop to the
  main actor explicitly (see the `MainActor.run` block above).
- `SpeechService` is an `actor`. Its `transcripts` and `errors` streams
  are `nonisolated` and may be observed independently.

## Style

- British English in comments and DocC.
- Public symbols use US-English spelling where it matches Apple
  convention (e.g. `Color`, `synchronize`).

## Releases

Releases are managed by [release-please](https://github.com/googleapis/release-please).
Merges to `main` open or update a release PR that maintains
`CHANGELOG.md`, bumps `version.txt`, and — when merged — creates the
matching git tag and GitHub Release. PR titles (the squash-merge commit
subject) should follow
[Conventional Commits](https://www.conventionalcommits.org/), e.g.:

- `feat: add streaming transcript filter` → minor bump
- `fix: handle empty script in tracker` → patch bump
- `feat!: rename SpeechService.consume` → major bump (after 1.0.0; before
  1.0.0 this is treated as a minor bump per the config)
- `docs:`, `chore:`, `refactor:`, `test:`, `build:`, `ci:` → no version
  bump

## Licence

[MIT](./LICENSE)
