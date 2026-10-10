# Yet Another Dictator — iOS

Native iOS companion to the [macOS Dictator app](https://github.com/captainDuckay/yet-another-dictator).

Fully offline dictation that works in any text field via a custom keyboard extension. Uses the shared [DictationCore](https://github.com/captains-chest/DictationCore) package and WhisperKit.

## Design goals

- **Simple and robust** — same philosophy as the macOS app: no fancy features, just reliable dictation.
- **Platform native** — floating-style mic button on the keyboard when a text field is focused.
- **Hold** = push-to-talk, **tap** = toggle (same dual-mode as the macOS hotkey).
- **Smaller model** — Whisper Small (or device-appropriate) via WhisperKit. Offline, on-device.
- **Shared core** — pure logic lives in DictationCore.

## Architecture

```
Main app (SwiftUI)
  └─ Settings, model management, permissions
Keyboard Extension
  └─ Mic button + standard keys
  └─ Implements TextInserting via UITextDocumentProxy
Shared
  └─ DictationCore (state machine, transcript processing)
  └─ WhisperKit adapter
```

Text insertion uses the keyboard's `textDocumentProxy`. Recording/transcription may be bridged to the main app via App Group if the extension memory limit is tight.

## Requirements

- iOS 18 or later (DictationCore 0.1.0 needs it), Xcode 26 / Swift 6.2.
- Dependencies are pinned exactly in `Package.swift` (DictationCore 0.1.0, WhisperKit 1.1.1), and
  `Package.resolved` is committed. Bump them deliberately; Dependabot proposes bumps as PRs.

## Privacy rules (same as the macOS app)

These are requirements for every change:

- **Offline dictation.** Audio and text never leave the device. The model is bundled (or
  explicitly installed by the user), and WhisperKit must never download on its own.
- **No clipboard.** Text goes in through `UITextDocumentProxy.insertText`, never the pasteboard.
- **Least privilege.** Full Access and App Groups only where strictly needed, explained in the PR.
  Nothing typed is stored or logged.

## Status

Early scaffolding: a SwiftPM package with `KeyboardTextInserter` (the `TextInserting` port on
`UITextDocumentProxy`) and design notes. There is **no Xcode project yet**: no app target, no
keyboard extension, no entitlements, no microphone capture, no bundled model, no tests and no CI.
A keyboard extension can't record audio itself, so capture needs a decision (see
`Sources/DictatorIOS/Notes.md`). A proposed CI workflow is in `docs/ci.yml`; move it to
`.github/workflows/` to enable it.

## Conventions

Conventional commits, a CHANGELOG (Keep a Changelog), ADRs in `docs/adr/` for decisions, exact
dependency pins, small PRs merged on green CI. These are the same conventions as the macOS app.

## License

MIT © 2026 Nicki Skipper Otte. See [LICENSE](LICENSE). Third-party components are credited in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
