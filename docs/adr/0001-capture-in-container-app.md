# 1. The container app records and transcribes; the keyboard gets the text through an App Group

- Status: Accepted
- Date: 2026-10-10

## Context

Dictation must work in any text field, so typing happens in a custom keyboard extension through
`UITextDocumentProxy`. Two limits rule out doing everything in the extension:

- **No microphone.** iOS doesn't let keyboard extensions record audio, even with Full Access.
- **Memory.** Keyboard extensions get a small, system-enforced memory budget (tens of MB), far
  below what a Whisper model plus audio buffers needs. An extension that goes over is killed.

## Decision

- The **container app** owns the whole pipeline, offline: it records with AVAudioEngine (16 kHz
  mono, the same `CaptureBuffer` as macOS), transcribes with WhisperKit and the bundled model
  (ADR 0003), and cleans up the text with DictationCore.
- The **keyboard extension** shows the mic button and inserts text. It starts and stops dictation
  through the container app, which records in the background while a session is active. The
  finished transcript comes back through a shared **App Group** container, signalled with a Darwin
  notification. The extension inserts it with `KeyboardTextInserter` and applies DictationCore's
  smart spacing using `documentContextBeforeInput`.
- What the hand-off holds: the latest transcript plus a session id, deleted as soon as it's
  inserted. No history and no audio. Nothing leaves the device.

## Consequences

- The extension needs `RequestsOpenAccess = YES` (Full Access) to use the shared container, and
  both targets need the App Group entitlement. The container app needs the microphone usage
  description and the audio background mode. Each one gets a one-line justification in the README.
- The first dictation may need a trip to the container app to start the session; the exact UX
  (and how long a session stays alive) is to be designed and measured on device.
- Full Access shows users a broad warning. We keep the extension network-free and say so plainly.
- The pipeline can be tested in the container app without the keyboard.
