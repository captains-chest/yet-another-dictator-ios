# 4. Download the model after an explicit opt-in

- Status: Accepted; amended by [ADR 0005](0005-choose-the-speech-model.md) (which model, chosen by the user)
- Date: 2026-10-11
- Supersedes: [ADR 0003](0003-small-bundled-model.md) (bundling only; Whisper Small stays the model)

## Context

ADR 0003 bundled Whisper Small (about 220 MB) and never downloaded. Every install and update carried
the model, and a larger or second model (e.g. Dansk-only) would grow the app for everyone. Phones
are often on metered connections, so a download must be the user's active decision.

## Decision

- The model is **not bundled**. The "Copy model manifest" build phase ships only
  `scripts/model-manifest.txt` (`<model-id> <sha256> <bytes> <huggingface-path> <local-path>`),
  sealed by the app's signature. **It is the trust anchor and is never fetched from the network.**
- The Model screen shows the model and its size and recommends Wi-Fi. Nothing downloads until the
  user taps **Download Model**. Mobile data is used only if they turn on **Use Mobile Data**, and on a
  cellular/expensive network they confirm it again. Otherwise the session waits for Wi-Fi
  (`allowsCellularAccess`, `allowsExpensiveNetworkAccess` and `allowsConstrainedNetworkAccess` off).
- `BackgroundTransport` uses a background `URLSession`, so the download continues while the app is
  suspended or after the system terminates it (`AppDelegate` forwards
  `handleEventsForBackgroundURLSession`). Failed tasks keep resume data and continue from it.
- `ModelInstaller` (shared with macOS) verifies each file's size and SHA-256 before moving it into
  place, retries with backoff, writes a `.complete` marker last, and deletes models that are no
  longer in the manifest.
- Files go to the **app container's** `Application Support/Models/<model-id>/`, excluded from
  backup. Not the App Group: the keyboard extension never loads the model (ADR 0001), so it
  doesn't need access, and the App Group stays limited to the transcript hand-off.
- Until the model is installed, transcription reports "The speech model isn't downloaded yet. Open
  Dictator to download it.", which the keyboard shows too.

## Consequences

- Wording changes to: "Audio never leaves the device; the one-time model download is the only
  network use." App Store privacy answers stay "Data Not Collected" (nothing from the user is sent).
- The app is about 220 MB smaller and can offer larger or extra models (a Dansk-only model is
  extra manifest lines) without growing.
- Dictation needs one online moment after install.
