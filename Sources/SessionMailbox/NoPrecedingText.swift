import DictationCore

/// The container app's `PrecedingTextReading` port: the app can't see the field being typed into,
/// so it never knows the text before the cursor. Only the keyboard can, and it does the smart
/// spacing itself from `documentContextBeforeInput` (see `KeyboardSession`).
@MainActor
public final class NoPrecedingText: PrecedingTextReading {
    public init() {}
    public func textBeforeCursor(maxLength: Int) -> String? { nil }
}
