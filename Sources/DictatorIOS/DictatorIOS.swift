// The app and the keyboard extension import this module. It re-exports the pieces they share.
// WhisperKit stays in `WhisperTranscription`, which only the app links (ADR 0001).
@_exported import DictationCore
@_exported import KeyboardInsertion
@_exported import SessionMailbox
