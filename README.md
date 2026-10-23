# Yet Another Dictator — iOS

Native iOS companion to the [macOS Dictator app](https://github.com/captains-chest/yet-another-dictator).

On-device dictation that works in any text field via a custom keyboard extension. Uses the shared [DictationCore](https://github.com/captains-chest/DictationCore) package and WhisperKit.

## Design goals

- **Simple and robust** — same philosophy as the macOS app: no fancy features, just reliable dictation.
- **Platform native** — floating-style mic button on the keyboard when a text field is focused.
- **Hold** = push-to-talk, **tap** = toggle (same dual-mode as the macOS hotkey).
- **Your choice of model** — NVIDIA Parakeet TDT 0.6B v2 (English, most accurate, about 464 MB, via FluidAudio), Phonon-2 (English, a smaller Parakeet, about 358 MB, via FluidAudio) or Whisper Small (Automatic or English, about 220 MB, via WhisperKit), on-device. Picked on first launch; only the chosen one is downloaded, after you opt in (Wi-Fi recommended).
- **Shared core** — pure logic lives in DictationCore.

## Architecture

Recording and transcription run in the container app. The keyboard only shows the mic button and
types. A keyboard extension cannot record audio, and it does not have the memory for a Whisper
model (ADR 0001).

```
Container app
  └─ AVAudioEngine → CaptureBuffer (16 kHz mono)
  └─ ActiveTranscriber → ParakeetTranscriber (Parakeet v2 or Phonon-2; FluidAudio, loadLocal only) or WhisperKitTranscriber
     (Whisper Small, WhisperKit download disabled), for the model chosen in the picker (ADR 0005)
  └─ ModelDownload → ModelInstaller + BackgroundTransport (opt-in, Wi-Fi by default, ADR 0004)
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
scripts/fetch-model.sh          # optional; verifies Whisper Small into ./Model for the end-to-end test
open DictatorIOS.xcodeproj
```

No build contains a model (ADR 0004). The app ships only `scripts/model-manifest.txt`, sealed by
its signature and never fetched. On first launch the user picks a model (best first, ADR 0005);
then on the Model screen they see its size and tap **Download Model**; Wi-Fi is the default, mobile data only if they turn it on and confirm. A background
`URLSession` keeps going while the app is suspended. Files land in `Application Support/Models`
(excluded from backup), each checked against its SHA-256 before use.

```sh
swift test                      # hand-off, insertion, and "model folder is complete" checks
```

## Entitlements

Each one is required for the hand-off in ADR 0001. The only network use is the opt-in model download in the container app (ADR 0004).

- **App Group** `group.com.captainduckay.dictator.ios` on the app and the keyboard: the in-flight
  transcript. Deleted once typed.
- **Full Access** (`RequestsOpenAccess`): the keyboard can read that container. The extension has
  no network code.
- **Microphone usage description:** the app records only while a dictation is running.
- **Audio background mode:** the armed session stays awake so the keyboard can start a recording
  while another app is in front. The microphone indicator is visible the whole time.

## Requirements

- iOS 18 or later (DictationCore 0.1.0 needs it), Xcode 26 / Swift 6.2.
- Dependencies are pinned exactly in `Package.swift` (DictationCore, WhisperKit 1.1.1, FluidAudio 0.17.7 with its NemoTextProcessing binary trait off), and
  `Package.resolved` is committed. Bump them deliberately; Dependabot proposes bumps as PRs.

## Privacy rules (same as the macOS app)

These are requirements for every change:

- **Audio never leaves the device; downloading the chosen model is the only network use.** The
  download needs the user's explicit opt-in, defaults to Wi-Fi, and is verified against the bundled
  manifest. WhisperKit and FluidAudio must never download on their own.
- **No clipboard.** Text goes in through `UITextDocumentProxy.insertText`, never the pasteboard.
- **Least privilege.** Full Access and App Groups only where strictly needed, explained in the PR.
  Nothing typed is stored or logged.

## Status

The container app, the keyboard extension, and the App Group hand-off are in place. The model is
pinned in `scripts/model-manifest.txt` and downloaded after install with the user's consent (ADR 0004).
CI (`.github/workflows/ci.yml`) runs `swift test` and builds the iOS app. How the two processes are
wired is in `docs/implementation-notes.md`. Peak memory, latency, and English quality on the
oldest supported iPhone are still to be measured before considering a larger model (ADR 0004 makes that a download, not an app-size question). How
long an armed session survives in the background needs the same on-device pass (ADR 0001).

## Conventions

Conventional commits, a CHANGELOG (Keep a Changelog), ADRs in `docs/adr/` for decisions, exact
dependency pins, small PRs merged on green CI. These are the same conventions as the macOS app.

## License

MIT © 2026 CaptainDuckay. See [LICENSE](LICENSE). Third-party components are credited in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Model attribution

The Parakeet model is "parakeet-tdt-0.6b-v2" by NVIDIA Corporation, licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
([source](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)), used as converted to Core ML by
[FluidInference](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml). See
`THIRD_PARTY_NOTICES.md`.

The Phonon-2 model is "Phonon-2" by Fermion Research, licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
([source](https://huggingface.co/FermionResearch/Phonon-2)), derived from NVIDIA's
[parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) (CC BY 4.0), used as
converted to Core ML by [FluidInference](https://huggingface.co/FluidInference/phonon-2-coreml).
