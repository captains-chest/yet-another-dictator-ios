# 5. Let the user choose the speech model; download only that one

- Status: Accepted
- Note (2026-10-15): Dictator is English-only; Dansk is no longer offered.
- Date: 2026-10-14
- Supersedes: the "Whisper Small stays the model" part of [ADR 0003](0003-small-bundled-model.md)
  and [ADR 0004](0004-download-model-after-opt-in.md). ADR 0004's opt-in, Wi-Fi default,
  background transport and verification still apply.

## Context

Whisper Small is the weakest of the candidates measured on 14 Oct 2026 (Open ASR Leaderboard).
NVIDIA Parakeet TDT 0.6B v2 is much more accurate for English (6.05 average WER), runs on the
Neural Engine, and has no 30-second window. It is English only, so Whisper Small stays for Automatic or English.
The macOS and Android apps get the same choice.

## Decision

- Two models, best first: **Parakeet TDT 0.6B v2** (`parakeet-tdt-0.6b-v2`, Core ML conversion
  `FluidInference/parakeet-tdt-0.6b-v2-coreml@ee09c56`, about 464 MB, run by FluidAudio 0.17.7 with
  its NemoTextProcessing binary trait off) and **Whisper Small** (unchanged).
- **No automatic download.** On launch, only if no model has been chosen, a picker sheet lists the
  models best first with size, languages, accuracy and speed. Choosing one downloads nothing: the
  Model section then asks for the download exactly as in ADR 0004 (Wi-Fi by default, mobile data
  only when turned on and confirmed). A copy that already has a verified Whisper Small download
  adopts it as the choice and is not asked.
- The choice is stored in UserDefaults (`speechModel`). The Models list switches model (download on
  demand, same opt-in) and deletes models not in use. Switching waits while a download runs.
- Both models are pinned, file by file with SHA-256 and size, in the bundled `model-manifest.txt`
  under their own model-id, and use the same `ModelInstaller` (resume, retry, verification).
- `ParakeetTranscription` is the only target that imports FluidAudio. It loads with
  `AsrModels.loadLocal` from the verified folder and never downloads. It does not use the Whisper
  30-second splitter; FluidAudio windows long audio itself. The keyboard extension still never loads
  a model (ADR 0001).
- Parakeet is English only; the language picker is disabled while it is in use.

## Consequences

- Parakeet is a larger download than Whisper Small and needs more memory while loading (about
  0.5-0.8 GB, container app only). Measure on the oldest supported iPhone.
- One more pinned dependency (FluidAudio, Apache 2.0, no transitive dependencies with the trait off).
