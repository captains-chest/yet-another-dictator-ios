# 3. Start with a small bundled Whisper model; never download

- Status: Accepted
- Date: 2026-10-10

## Context

The macOS app bundles Whisper Large v3 Turbo (about 1.6 GB). An iPhone has less memory and
storage, transcription runs in the container app (ADR 0001), and dictation must work offline from
the first launch. Danish and English are both needed, so English-only models are out.

## Decision

- Start with **`openai_whisper-small_216MB`** from argmaxinc/whisperkit-coreml: multilingual,
  compressed to about 216 MB.
- Bundle it in the app. WhisperKit is configured with `download: false`, and loading fails
  loudly if a file is missing, as on macOS.
- Pin every file to an immutable Hugging Face commit with a SHA-256 manifest, the same format as
  the macOS `scripts/model-manifest.txt`. A fetch script verifies it, and dependencies stay pinned
  exactly.
- **Measure before upsizing.** Record peak memory, load time, latency and Danish/English quality
  on the oldest supported iPhone. Consider a bigger model (e.g. `large-v3-v20240930_626MB`) only
  if Small isn't good enough and the numbers allow it. The switch gets its own ADR.

## Consequences

- Small is less accurate than the macOS model, especially for Danish. That is accepted for now.
- License: the Core ML conversion is MIT (argmax). The OpenAI Whisper Small weights and tokenizer
  are **Apache 2.0**. Both are compatible and credited in `THIRD_PARTY_NOTICES.md`.
- The app is about 220 MB larger. That's acceptable and below the cellular download limit.
