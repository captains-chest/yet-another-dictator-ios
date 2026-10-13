# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- Dictator is English-only. The Dansk language option is removed; Whisper offers Automatic or English. Parakeet remains English only.

### Fixed
- Dictations longer than 30 seconds no longer lose words. Whisper hears 30 seconds at a time, and the audio was cut into fixed 30-second pieces: a word on a cut could be split or lost, and a last piece shorter than a second was skipped, cutting off the end. Long recordings are now cut at a pause, and no piece is too short to be transcribed.
- Consecutive dictations no longer get a double smart-spacing adjustment. The container hands off
  the cleaned transcript raw (`NoPrecedingText.usesHistoryForJoining = false` on DictationCore
  0.2.1); only the keyboard joins against `documentContextBeforeInput`.

## [0.2.0] - 2026-10-15

### Added
- A second speech model: NVIDIA Parakeet TDT 0.6B v2, English only, the most accurate (about 464 MB). Whisper Small stays available, and is the one to use for Dansk. Parakeet is licensed CC-BY-4.0 and credited in the license notices.
- On first launch Dictator asks which model to use, best first, with the size, accuracy and speed of each. It downloads nothing until you choose and confirm, and only the model you chose, still over Wi-Fi unless you allow mobile data. A Whisper Small download from before stays in use without asking. Switch models or delete one you no longer use on the Models list.
- MIT license and third-party notices.
- Dependabot weekly updates for Swift packages and GitHub Actions.
- Container app that records and transcribes with the bundled Whisper Small model, and a keyboard
  extension that types the result through the App Group hand-off (ADR 0001).
- SHA-256 model manifest and `scripts/fetch-model.sh` for `openai_whisper-small_216MB` (ADR 0003).
- CI workflow that runs the package tests and builds the iOS app.
- Undo Last Dictation: after a dictation, the keyboard shows an Undo button that deletes exactly
  what that dictation typed (including any space it added in front), like the Mac app. It's only
  offered while the cursor is still right after the dictated text in the same field; once you type,
  move the cursor, select text or switch fields, the dictation is no longer undoable.

### Changed
- The speech model is no longer inside the app, so the app is about 220 MB smaller. The Model screen shows the size and downloads it only when you tap Download Model, over Wi-Fi unless you turn on mobile data and confirm. The download keeps going in the background, resumes after interruptions, and every file is checked against a SHA-256 list built into the app (ADR 0004, supersedes ADR 0003). Audio never leaves the device; the one-time model download is the only network use.
- Third-party notices: OpenAI's Whisper weights are MIT licensed, not Apache 2.0.
- `KeyboardTextInserter` (now in the tested `KeyboardInsertion` target) throws when there is no text field instead of silently dropping the dictation, and inserts in chunks that stop when the dictation is cancelled, like the macOS inserter.
- DictationCore is pinned exactly (currently 0.2.1); the minimum is iOS 18.

### Fixed
- Consecutive dictations no longer get a double smart-spacing adjustment. The container hands off
  the cleaned transcript raw (`NoPrecedingText.usesHistoryForJoining = false` on DictationCore
  0.2.1); only the keyboard joins against `documentContextBeforeInput`.
