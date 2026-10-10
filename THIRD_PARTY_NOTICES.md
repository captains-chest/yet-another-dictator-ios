# Third-party notices

Yet Another Dictator for iOS is MIT licensed (see `LICENSE`). It depends on the following
third-party pieces, all under licenses compatible with that. Bundle this file (or its content) in
the app's acknowledgements when the app ships.

| Component | Used for | License | Source |
| --- | --- | --- | --- |
| WhisperKit 1.1.1 | On-device speech recognition | MIT, © 2024 argmax, inc. | https://github.com/argmaxinc/WhisperKit |
| WhisperKit Core ML models | Speech model (Core ML conversion), once one is bundled | MIT (argmax, inc.) | https://huggingface.co/argmaxinc/whisperkit-coreml |
| OpenAI Whisper weights and tokenizer | The original model (e.g. Large v3 Turbo is MIT; check the card of whichever size is chosen) | MIT, © 2022 OpenAI | https://github.com/openai/whisper |
| DictationCore 0.1.0 | Shared dictation logic | MIT, © 2026 Nicki Skipper Otte | https://github.com/captains-chest/DictationCore |

`swift-argument-parser` (Apache 2.0) is in `Package.resolved` only because WhisperKit's
command-line tool needs it; the app doesn't link it.

Each MIT component is used under the MIT license text in `LICENSE`, with its own copyright notice.
