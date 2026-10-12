# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
- Consecutive dictations no longer get a double smart-spacing adjustment. The container hands off
  the cleaned transcript raw (`NoPrecedingText.usesHistoryForJoining = false` on DictationCore
  0.2.1); only the keyboard joins against `documentContextBeforeInput`.

### Added
- MIT license and third-party notices.
- Dependabot weekly updates for Swift packages and GitHub Actions.
- Container app that records and transcribes with the bundled Whisper Small model, and a keyboard
  extension that types the result through the App Group hand-off (ADR 0001).
- SHA-256 model manifest and `scripts/fetch-model.sh` for `openai_whisper-small_216MB` (ADR 0003).
- CI workflow that runs the package tests and builds the iOS app.

### Changed
- `KeyboardTextInserter` (now in the tested `KeyboardInsertion` target) throws when there is no text field instead of silently dropping the dictation, and inserts in chunks that stop when the dictation is cancelled, like the macOS inserter.
- DictationCore is pinned exactly (currently 0.2.1); the minimum is iOS 18.
