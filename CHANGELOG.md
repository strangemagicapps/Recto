# Changelog

## [0.1.1](https://github.com/strangemagicapps/Recto/compare/0.1.0...0.1.1) (2026-05-16)


### Bug Fixes

* **speech:** use callback-based AVAudioConverter for SR conversion ([88ec8dc](https://github.com/strangemagicapps/Recto/commit/88ec8dcc099d6a6c6410257dcd22fb0ad489845e))

## 0.1.0 (2026-05-16)

Initial public release of Recto. The v1 surface is the script-following
core shared by Quarto (macOS surtitles) and Octavo (iOS autocue): script
parsing, fuzzy live-position tracking, and an on-device speech
recognition actor built on the iOS 26 / macOS 26 `SpeechAnalyzer` +
`SpeechTranscriber` APIs.


### Features

* **parser:** add `ParsedScript` and `ScriptParser` for normalising raw script text into matchable token streams ([#7](https://github.com/strangemagicapps/Recto/pull/7)) ([6d66a94](https://github.com/strangemagicapps/Recto/commit/6d66a9461d4c6f8ff80c5c2bba5d750d2aaf8a82))
* **tracker:** add `ScriptTracker` matcher with configurable look-ahead window, offset, and single-word fallback ([#8](https://github.com/strangemagicapps/Recto/pull/8)) ([1b84731](https://github.com/strangemagicapps/Recto/commit/1b84731954dfab88ad0077904ee2843554e77e9f))
* **speech:** add `SpeechService` actor wrapping `SpeechAnalyzer` + `SpeechTranscriber` with `transcripts` and `errors` async streams ([#9](https://github.com/strangemagicapps/Recto/pull/9)) ([bd8a0c1](https://github.com/strangemagicapps/Recto/commit/bd8a0c172dbf5a6b9672c8495096b7f4ad649d3f))
* **audio:** add `AudioBufferConverter` helper for turning `AVAudioPCMBuffer` taps into `CMSampleBuffer` inputs for `SpeechService` ([#10](https://github.com/strangemagicapps/Recto/pull/10)) ([b6d3d75](https://github.com/strangemagicapps/Recto/commit/b6d3d75157cb5237bc91edf0e7f9c18e618917bb))


### Documentation

* add DocC catalog and full documentation pass covering the public API surface ([#11](https://github.com/strangemagicapps/Recto/pull/11)) ([44dc69f](https://github.com/strangemagicapps/Recto/commit/44dc69fb10fac38910e475cf2fbcd6aa032cb838))
* add BRIEF.md ([2e5ef87](https://github.com/strangemagicapps/Recto/commit/2e5ef87bf5f91403f7882117398784ec7225f031))


### Build

* ignore `.swiftpm/` ([#12](https://github.com/strangemagicapps/Recto/pull/12)) ([2637ac5](https://github.com/strangemagicapps/Recto/commit/2637ac53b472ce725204f24bfb0cdd49be5adbad))
