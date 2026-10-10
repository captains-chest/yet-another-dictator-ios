# Implementation notes for the iOS keyboard

## Keyboard extension setup (in Xcode)

1. Add a Keyboard Extension target to the iOS app.
2. In the extension's Info.plist, set `RequestsOpenAccess` if full access is required for mic (usually yes).
3. Request microphone permission in the main app and share via App Group if needed.

## Mic button UX

- Place a large mic button prominently on the keyboard view (SwiftUI hosted in UIInputViewController).
- Gesture: UILongPressGestureRecognizer or SwiftUI gesture for hold (PTT) and tap (toggle).
- On press: call `controller.hotkeyPressed()`.
- On release (if held long enough): call `controller.hotkeyReleased()`.

## Audio recording

Implement `AudioRecording` using AVAudioEngine in the main app or carefully in the extension.
If memory is constrained in the extension, record in the main app and communicate via App Group + Darwin notification.

## Model

Start with Whisper Small. Load via WhisperKit in the main app or extension depending on measurements.
Reuse the same prompt, cleaning, and SmartJoin from DictationCore.

## Next steps

- Create the actual Xcode project with App + Keyboard Extension targets.
- Wire the DictationController with the keyboard inserter and a microphone recorder.
- Design the minimal keyboard UI with the mic button.
