# Third-party notices

Yet Another Dictator for iOS is MIT licensed (see `LICENSE`). It depends on the following
third-party pieces, all under licenses compatible with that. Bundle this file (or its content) in
the app's acknowledgements when the app ships.

| Component | Used for | License | Source |
| --- | --- | --- | --- |
| WhisperKit 1.1.1 | On-device speech recognition | MIT, © 2024 argmax, inc. | https://github.com/argmaxinc/WhisperKit |
| WhisperKit Core ML model `openai_whisper-small_216MB` | Speech model, downloaded after the user opts in (Core ML conversion; ADR 0004) | MIT (argmax, inc.) | https://huggingface.co/argmaxinc/whisperkit-coreml |
| OpenAI Whisper Small weights and tokenizer | The original model the conversion is made from | MIT, © 2022 OpenAI | https://huggingface.co/openai/whisper-small |
| DictationCore 0.1.0 | Shared dictation logic | MIT, © 2026 CaptainDuckay | https://github.com/captains-chest/DictationCore |

`swift-argument-parser` (Apache 2.0) is in `Package.resolved` only because WhisperKit's
command-line tool needs it; the app doesn't link it.

Each MIT component is used under the MIT license text in `LICENSE`, with its own copyright notice.
The Whisper Small weights and tokenizer are MIT licensed (© 2022 OpenAI,
https://github.com/openai/whisper/blob/main/LICENSE). The model is downloaded after install, not
bundled (ADR 0004).
