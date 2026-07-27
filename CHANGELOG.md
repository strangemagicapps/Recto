# Changelog

## [0.1.6](https://github.com/strangemagicapps/Recto/compare/0.1.5...0.1.6) (2026-07-27)


### Features

* add segment parser for display-only words ([#36](https://github.com/strangemagicapps/Recto/issues/36)) ([d03c0d4](https://github.com/strangemagicapps/Recto/commit/d03c0d42ac81a1d00e87bbce46248f712295777a))
* segment parser for display-only words ([#34](https://github.com/strangemagicapps/Recto/issues/34)) ([54f2728](https://github.com/strangemagicapps/Recto/commit/54f2728db110bf1de2696412102f4731ee7333fc))


### Documentation

* add contributing guidelines and code of conduct ([#33](https://github.com/strangemagicapps/Recto/issues/33)) ([0aad5f5](https://github.com/strangemagicapps/Recto/commit/0aad5f5efb9849ecd79ebd0fca826dddb8660c06))
* fix typo in Recto.docc overview (coompact -&gt; compact) ([d185c5b](https://github.com/strangemagicapps/Recto/commit/d185c5b390eefe71a52c5eb48dcf9893cb5dee8a))
* Update build badge ([d88cee5](https://github.com/strangemagicapps/Recto/commit/d88cee56aab5c14b485c28df7b6aa5ff4e5185b0))
* Use correct repo URL in package example ([05350c8](https://github.com/strangemagicapps/Recto/commit/05350c8659f835a3cfa8c40f83520f219dc4f6dd))

## [0.1.5](https://github.com/strangemagicapps/Recto/compare/0.1.4...0.1.5) (2026-06-01)


### Documentation

* Add shields.io badges to README and docs ([#29](https://github.com/strangemagicapps/Recto/issues/29)) ([69d2f8c](https://github.com/strangemagicapps/Recto/commit/69d2f8c8143e938295d08cfe060c9cccd21ea544))

## [0.1.4](https://github.com/strangemagicapps/Recto/compare/0.1.3...0.1.4) (2026-06-01)


### Documentation

* Update README with tvOS/visionOS requirements ([#27](https://github.com/strangemagicapps/Recto/issues/27)) ([593f00a](https://github.com/strangemagicapps/Recto/commit/593f00a15673e3cfc5929bff6bce6c9c680d2c10))

## [0.1.3](https://github.com/strangemagicapps/Recto/compare/0.1.2...0.1.3) (2026-05-31)


### Bug Fixes

* **docs:** Typos and Octavo -&gt; Lilt remnants ([f0c04f8](https://github.com/strangemagicapps/Recto/commit/f0c04f81e3672bf568d92d1d98c483d82cb11274))


### Documentation

* expand DocC symbol documentation and usage examples ([#24](https://github.com/strangemagicapps/Recto/issues/24)) ([4c17cf2](https://github.com/strangemagicapps/Recto/commit/4c17cf2a2893d94d0498eba45b2d36e16cf32d91))
* link the README to the published GitHub Pages documentation ([#25](https://github.com/strangemagicapps/Recto/issues/25)) ([1d1ece4](https://github.com/strangemagicapps/Recto/commit/1d1ece4ba22b5397a9b9cd15ec7d54e97f7970af))

## [0.1.2](https://github.com/strangemagicapps/Recto/compare/0.1.1...0.1.2) (2026-05-27)


### Features

* decouple displayed tokens from matchable tokens ([#15](https://github.com/strangemagicapps/Recto/issues/15)) ([a15d997](https://github.com/strangemagicapps/Recto/commit/a15d99743d1884b9a7fb248d0cbe793e0220859f))
* **parser:** preserve blank lines / stanza breaks in ScriptParser output ([#19](https://github.com/strangemagicapps/Recto/issues/19)) ([9219a74](https://github.com/strangemagicapps/Recto/commit/9219a74d36950162f9dd7bd6a27c8ba8c9be9ff1))


### Documentation

* Update app name from Octavo to Lilt in README ([#17](https://github.com/strangemagicapps/Recto/issues/17)) ([a2a2a05](https://github.com/strangemagicapps/Recto/commit/a2a2a051a9fa4cc171ed9a94c595087166affe0f))

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
