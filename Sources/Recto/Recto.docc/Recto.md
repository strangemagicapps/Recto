# ``Recto``

A small, shared script-following engine for the Strange Magic page-format
apps.

## Overview

 [![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fstrangemagicapps%2FRecto%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/strangemagicapps/Recto) [![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fstrangemagicapps%2FRecto%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/strangemagicapps/Recto)

Recto is a Swift package providing the script model, the matcher, and
the on-device speech recognition service shared by **Quarto** (the
macOS surtitle engine) and **Lilt** (the iOS autocue app). The
package contains no UI, no persistence, and no platform-specific
capture pipeline; consuming apps own those concerns.

The name follows the Strange Magic bibliographic family. *Recto* is the
right-hand page of an open book — the side a reader's eye falls on
first; the package sits underneath the page-format apps as the shared
text they both rest on.

The page-format apps take their names from book-folding terms. **Quarto**,
the macOS surtitle engine, and **Lilt**, the iOS autocue app, are the two
consumers Recto serves; both fold the same parsed script into their own
presentation. *Lilt* was developed under the working title **Octavo** – a
smaller, more compact format. References to Octavo in earlier commits, issues,
and notes describe the project now being released as Lilt — there is no separate
Octavo app.

### What's in the box

- ``ParsedScript`` — a `Sendable` value type holding the tokenised
  script in both display and normalised forms.
- ``ScriptParser`` — the stateless parser that produces a
  ``ParsedScript`` from raw text.
- ``ScriptTracker`` — an `@MainActor @Observable` cursor that advances
  through a ``ParsedScript`` as recognised transcripts arrive.
- ``SpeechService`` — an actor wrapping the iOS 26 / macOS 26
  `SpeechAnalyzer` + `SpeechTranscriber` APIs. Accepts
  `CMSampleBuffer`s, publishes cumulative transcripts and non-fatal
  errors on independent `AsyncStream`s.
- ``AudioBufferConverter`` — a stateless helper that wraps an
  `AVAudioPCMBuffer` (produced by `AVAudioEngine` taps) in a
  `CMSampleBuffer` for consumption by ``SpeechService``.

### What's deliberately not

- No UI. Consumers render the script themselves; ``ScriptTracker`` is
  observable so SwiftUI views can bind to
  ``ScriptTracker/currentDisplayIndex`` directly.
- No persistence. Scripts are parsed from raw text supplied by the
  caller; saving and loading are the consuming app's responsibility.
- No capture pipeline. Recto accepts already-captured audio buffers; it
  does not own `AVAudioEngine`, `AVCaptureSession`, or microphone
  permission flows.
- No fuzzy matching, ML models, or extra probe strategies. The
  3 / 2 / 1-word probes and the 80-character transcript tail are tuned
  from empirical use in the sibling apps and should not change without
  evidence from real usage.

### Pipeline

The five types compose into a single audio-to-cursor pipeline:

![Recto pipeline: AVAudioPCMBuffer flows through AudioBufferConverter to CMSampleBuffer, into SpeechService, whose transcripts stream feeds ScriptTracker, whose currentDisplayIndex drives the UI.](pipeline.svg)

iOS apps that already produce `CMSampleBuffer`s — for example via
`AVCaptureSession` — can skip the converter and feed buffers directly
into ``SpeechService/consume(_:)``. For more details, see ``AudioBufferConverter``.

## Topics

### Script model

- ``ParsedScript``
- ``ScriptParser``

### Matching

- ``ScriptTracker``

### Speech recognition

- ``SpeechService``
- ``AudioBufferConverter``
