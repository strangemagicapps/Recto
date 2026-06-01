# Contributing to Recto

Thanks for your interest in contributing. Recto is the shared
script-following engine used by **Quarto** (macOS surtitle engine) and
**Lilt** (iOS autocue app). It is deliberately small — the script model,
the matcher, and the on-device speech recognition service — with no UI,
no persistence, and no platform-specific capture pipeline. Please keep
changes within that remit.

## Code of conduct

Be respectful and constructive. We follow the spirit of the
[Contributor Covenant](https://www.contributor-covenant.org/): assume
good faith, keep discussion focused on the work, and make this a project
people are glad to take part in.

## Getting started

### Requirements

- Swift 6.3 toolchain (Xcode 26)
- A platform target of iOS 26 / iPadOS 26 / macOS 26 / tvOS 26 /
  visionOS 26 or later

Recto uses system frameworks only (`Foundation`, `Speech`,
`AVFoundation`) plus `swift-docc-plugin` for documentation. It builds on
the new `SpeechAnalyzer` + `SpeechTranscriber` APIs and does **not** use
the older `SFSpeechRecognizer` recognition API.

### Build and test

```sh
swift build
swift test
```

Tests use the [Swift Testing](https://developer.apple.com/documentation/testing)
framework (`import Testing`, `@Suite`, `@Test`), not XCTest. New code
should come with tests. A change to the matcher, parser, or speech
service without accompanying tests is unlikely to be merged.

## Reporting issues

Before opening an issue, please search existing issues to avoid
duplicates. A good bug report includes:

- What you expected to happen and what actually happened.
- A minimal, self-contained reproduction — ideally a failing `@Test`.
- The OS and Swift toolchain versions.

For feature requests, describe the use case in the consuming app (Quarto
or Lilt, or your own) rather than only the proposed API. That helps keep
the public surface small and well-motivated.

## Pull requests

1. Open an issue first for anything beyond a small fix, so the approach
   can be agreed before you invest time.
2. Fork the repository and create a branch from `main`.
3. Make your change, keeping it focused — one logical change per PR.
4. Add or update tests, and make sure `swift build` and `swift test`
   both pass.
5. Update DocC documentation comments for any change to public API.
6. Open the pull request against `main`.

### Commit and PR titles

Pull requests are squash-merged, so the **PR title becomes the commit
subject** and drives releases. Titles must follow
[Conventional Commits](https://www.conventionalcommits.org/):

- `feat: add streaming transcript filter` → minor bump
- `fix: handle empty script in tracker` → patch bump
- `feat!: rename SpeechService.consume` → major bump (after 1.0.0;
  before 1.0.0 this is treated as a minor bump per the release config)
- `docs:`, `chore:`, `refactor:`, `test:`, `build:`, `ci:` → no version
  bump

Releases are managed by
[release-please](https://github.com/googleapis/release-please): merges to
`main` open or update a release PR that maintains `CHANGELOG.md` and
creates the matching tag and GitHub Release when merged. You do not need
to edit `CHANGELOG.md` or the version yourself.

## Coding style

- **Concurrency:** Swift 6 language mode with strict concurrency and
  main-actor-by-default isolation. `ParsedScript` is `Sendable`;
  `ScriptTracker` is `@MainActor`-isolated and deliberately not
  `Sendable`; `SpeechService` is an `actor`. Preserve these boundaries.
- **Language:** British English in comments and DocC. Public symbols use
  US-English spelling where it matches Apple convention (e.g. `Color`,
  `synchronize`).
- **Public API:** Keep it minimal. Every public symbol needs DocC
  documentation. Match the surrounding code's naming and idiom.

## Licence

By contributing, you agree that your contributions will be licensed under
the project's [MIT Licence](./LICENSE).
