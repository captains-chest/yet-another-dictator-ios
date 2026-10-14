# Third-party notices

Yet Another Dictator for iOS is MIT licensed (see `LICENSE`). It depends on the following
third-party pieces, all under licenses compatible with that. Bundle this file (or its content) in
the app's acknowledgements when the app ships.

| Component | Used for | License | Source |
| --- | --- | --- | --- |
| WhisperKit 1.1.1 | On-device speech recognition | MIT, © 2024 argmax, inc. | https://github.com/argmaxinc/WhisperKit |
| WhisperKit Core ML model `openai_whisper-small_216MB` | Speech model, downloaded after the user opts in (Core ML conversion; ADR 0004) | MIT (argmax, inc.) | https://huggingface.co/argmaxinc/whisperkit-coreml |
| OpenAI Whisper Small weights and tokenizer | The original model the conversion is made from | MIT, © 2022 OpenAI | https://huggingface.co/openai/whisper-small |
| FluidAudio 0.17.7 | Runs the Parakeet model on Core ML (the optional NemoTextProcessing binary is turned off) | Apache 2.0, © FluidInference | https://github.com/FluidInference/FluidAudio |
| NVIDIA Parakeet TDT 0.6B v2 (Core ML conversion `FluidInference/parakeet-tdt-0.6b-v2-coreml`) | English speech model, downloaded only if the user chooses it and opts in (ADR 0005) | CC-BY-4.0, © NVIDIA Corporation; converted to Core ML by FluidInference | https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2, https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml |
| DictationCore 0.1.0 | Shared dictation logic | MIT, © 2026 CaptainDuckay | https://github.com/captains-chest/DictationCore |

`swift-argument-parser` (Apache 2.0) is in `Package.resolved` only because WhisperKit's
command-line tool needs it; the app doesn't link it.

**Attribution (CC-BY-4.0):** "parakeet-tdt-0.6b-v2" by NVIDIA Corporation, licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Source:
https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2. Modified: converted to Core ML by
FluidInference (https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml); the app
downloads that conversion unchanged. FluidAudio is licensed under the Apache License 2.0
(https://www.apache.org/licenses/LICENSE-2.0).

Each MIT component is used under the MIT license text in `LICENSE`, with its own copyright notice.
The Whisper Small weights and tokenizer are MIT licensed (© 2022 OpenAI,
https://github.com/openai/whisper/blob/main/LICENSE). The model is downloaded after install, not
bundled (ADR 0004).
