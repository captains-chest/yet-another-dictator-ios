# Yet Another Dictator — iOS

Native iOS companion to the [macOS Dictator app](https://github.com/captains-chest/yet-another-dictator).

Fully offline dictation that works in any text field via a custom keyboard extension. Uses the shared [DictationCore](https://github.com/captains-chest/DictationCore) package and WhisperKit.

## Design goals

- **Simple and robust** — same philosophy as the macOS app: no fancy features, just reliable dictation.
- **Platform native** — floating-style mic button on the keyboard when a text field is focused.
- **Hold** = push-to-talk, **tap** = toggle (same dual-mode as the macOS hotkey).
- **Smaller model** — Whisper Small (or device-appropriate) via WhisperKit. Offline, on-device.
- **Shared core** — pure logic lives in DictationCore.

## Architecture

Recording and transcription run in the container app. The keyboard only shows the mic button and
types. A keyboard extension cannot record audio, and it does not have the memory for a Whisper
model (ADR 0001).

```
Container app
  └─ AVAudioEngine → CaptureBuffer (16 kHz mono)
  └─ WhisperKitTranscriber (bundled Whisper Small, download disabled)
  └─ DictationController
  └─ HandoffInserter writes the transcript into the App Group
Keyboard extension
  └─ Mic button: tap toggles, hold is push-to-talk
  └─ SmartJoin using documentContextBeforeInput
  └─ KeyboardTextInserter → UITextDocumentProxy.insertText
Shared package
  └─ DictatorIOS (re-exports the pieces both targets use; no WhisperKit)
  └─ SessionMailbox (commands, one transcript, Darwin wake-up)
  └─ WhisperTranscription (app only)
  └─ DictationCore
```

The shared container holds the latest transcript and a session id. The keyboard deletes it as soon
as it has typed. No audio and no history are written. The first session is started in the app
("Keep dictation available"): the microphone stays open so iOS doesn't suspend the process, and the
microphone indicator stays visible until the session is turned off.

## Build

Requires iOS 18+, Xcode 26 / Swift 6.2.

```sh
scripts/fetch-model.sh          # once; verifies Whisper Small into ./Model (gitignored)
open DictatorIOS.xcodeproj
```

The app copies `Model/` into its bundle when that folder exists. Without it, the app still builds
and refuses to transcribe. `Model/` is not downloaded by WhisperKit.

```sh
swift test                      # hand-off, insertion, and "model folder is complete" checks
```

## Entitlements

Each one is required for the hand-off in ADR 0001, and none of them grant network access.

- **App Group** `group.com.captainduckay.dictator.ios` on the app and the keyboard: the in-flight
  transcript. Deleted once typed.
- **Full Access** (`RequestsOpenAccess`): the keyboard can read that container. The extension has
  no network code.
- **Microphone usage description:** the app records only while a dictation is running.
- **Audio background mode:** the armed session stays awake so the keyboard can start a recording
  while another app is in front. The microphone indicator is visible the whole time.

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

The container app, the keyboard extension, and the App Group hand-off are in place. The model is
pinned in `scripts/model-manifest.txt` and bundled by `scripts/fetch-model.sh`; it is not committed.
CI (`.github/workflows/ci.yml`) runs `swift test` and builds the iOS app. How the two processes are
wired is in `docs/implementation-notes.md`. Peak memory, latency, and Danish/English quality on the
oldest supported iPhone are still to be measured before considering a larger model (ADR 0003). How
long an armed session survives in the background needs the same on-device pass (ADR 0001).

## Conventions

Conventional commits, a CHANGELOG (Keep a Changelog), ADRs in `docs/adr/` for decisions, exact
dependency pins, small PRs merged on green CI. These are the same conventions as the macOS app.

## License

MIT © 2026 Nicki Skipper Otte. See [LICENSE](LICENSE). Third-party components are credited in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
