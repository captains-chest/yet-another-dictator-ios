# Implementation notes

Capture, the model, and the iOS 18 minimum are decided in `docs/adr/`. This file is how that is
wired.

## Processes

- **Dictator** (container app) records with `MicrophoneRecorder`, transcribes with
  `WhisperKitTranscriber`, and runs `DictationController`. `SessionHost` applies keyboard commands.
- **DictatorKeyboard** shows the mic button and types with `KeyboardTextInserter`. It links
  `DictatorIOS` only, so WhisperKit is not in the extension.
- **SessionMailbox** is the App Group folder: a command queue, `host.json`, one `delivery.json`,
  and an ack. Darwin notifications (`SessionSignal`) wake the other process. The files are the data.

The keyboard decides tap versus hold (`KeyboardSession.holdThreshold`, 0.35s, the same default as
`DictationController`). A hold or a second tap sends `finish`. The app may apply both messages in
one turn, and the controller would otherwise see no time pass between press and release.

Smart spacing runs in the keyboard, from `documentContextBeforeInput`. The app can't see the field,
so its controller gets `NoPrecedingText`, a `PrecedingTextReading` port that always returns nil.

## Session

"Keep dictation available" activates an `AVAudioSession` record session and leaves the engine
running (0.4s pre-roll). That is what keeps the app awake for the keyboard. Turning it off stops
the engine. The keyboard treats a host heartbeat older than 3 seconds as gone.

## Model

`scripts/fetch-model.sh` fills `./Model` from `scripts/model-manifest.txt`. The app's "Copy bundled
model" build phase copies it into the bundle when the folder exists. `WhisperKitConfig.download` is
false, and `prepare()` throws if a required file is missing.

## Still to measure on a device

- Peak memory, load time, latency, and Danish/English quality of Whisper Small.
- How long an armed session stays alive in the background, and whether the always-on microphone
  indicator is acceptable.
