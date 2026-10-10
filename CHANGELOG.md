# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- MIT license and third-party notices.
- Dependabot weekly updates for Swift packages and GitHub Actions.
- Container app that records and transcribes with the bundled Whisper Small model, and a keyboard
  extension that types the result through the App Group hand-off (ADR 0001).
- SHA-256 model manifest and `scripts/fetch-model.sh` for `openai_whisper-small_216MB` (ADR 0003).
- CI workflow that runs the package tests and builds the iOS app.

### Changed
- `KeyboardTextInserter` (now in the tested `KeyboardInsertion` target) throws when there is no text field instead of silently dropping the dictation, and inserts in chunks that stop when the dictation is cancelled, like the macOS inserter.
- DictationCore is pinned exactly to 0.1.0 instead of following its `main` branch; the minimum is
  iOS 18.
