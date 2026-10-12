import DictationCore

/// The container app's `PrecedingTextReading` port: the app can't see the field being typed into,
/// so it never knows the text before the cursor. Only the keyboard can, and it does the smart
/// spacing itself from `documentContextBeforeInput` (see `KeyboardSession`).
///
/// `usesHistoryForJoining` is false so `DictationController` hands off the cleaned transcript raw
/// instead of SmartJoining against its own dictation history (which would double-space once the
/// keyboard joins again).
@MainActor
public final class NoPrecedingText: PrecedingTextReading {
    public init() {}
    public var usesHistoryForJoining: Bool { false }
    public func textBeforeCursor(maxLength: Int) -> String? { nil }
}
