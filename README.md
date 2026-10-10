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

## Getting started

1. Open in Xcode (create an iOS App + Keyboard Extension targets).
2. Add the DictationCore package dependency.
3. Add WhisperKit.
4. Implement the ports in the keyboard extension.

## Status

Early scaffolding. Core logic is shared; platform adapters and UI are next.
