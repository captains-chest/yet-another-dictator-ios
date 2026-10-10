import DictationCore
import Foundation

/// `TextInserting` for the container app. Writes the transcript into the mailbox and waits until
/// the keyboard confirms it was typed. Never touches the pasteboard, and never stores a history:
/// the file is claimed by the keyboard as it types.
@MainActor
public final class HandoffInserter: TextInserting {
    public enum Failure: LocalizedError, Equatable {
        case timedOut
        case rejected(String)

        public var errorDescription: String? {
            switch self {
            case .timedOut:
                "The keyboard didn't confirm that the dictation was typed."
            case .rejected(let message):
                message
            }
        }
    }

    /// How long a live dictation waits for the keyboard, which is already on screen.
    public static let defaultAckTimeout: Duration = .seconds(20)
    public static let defaultPollInterval: Duration = .milliseconds(40)

    /// The press that started the dictation currently being transcribed. Set by `SessionHost`.
    public var commandID: UUID?
    /// A retry from the app: the keyboard didn't just start this gesture, but should still type it.
    public var acceptsWithoutCommand = false

    private let mailbox: SessionMailbox
    private let post: (SessionSignal) -> Void
    private let now: () -> TimeInterval
    private let ackTimeout: Duration
    private let pollInterval: Duration

    public init(
        mailbox: SessionMailbox,
        post: @escaping (SessionSignal) -> Void = { $0.post() },
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
        ackTimeout: Duration = HandoffInserter.defaultAckTimeout,
        pollInterval: Duration = HandoffInserter.defaultPollInterval
    ) {
        self.mailbox = mailbox
        self.post = post
        self.now = now
        self.ackTimeout = ackTimeout
        self.pollInterval = pollInterval
    }

    /// The keyboard checks the text field before it asks to record. There is nothing to preflight
    /// in the app: the field lives in the other process.
    public func preflight() throws {}

    public func insert(_ text: String) async throws {
        try await deliver(text: text, deleteCount: nil)
    }

    public func deleteBackward(_ count: Int) async throws {
        guard count > 0 else { return }
        try await deliver(text: "", deleteCount: count)
    }

    private func deliver(text: String, deleteCount: Int?) async throws {
        let solicited = commandID != nil && !acceptsWithoutCommand
        let delivery = DictationDelivery(
            id: UUID(),
            commandID: commandID ?? UUID(),
            text: text,
            deleteCount: deleteCount,
            acceptsWithoutCommand: !solicited,
            createdAt: now()
        )
        try mailbox.writeDelivery(delivery)
        post(.delivery)
        try await waitForAck(delivery.id)
    }

    private func waitForAck(_ id: UUID) async throws {
        let deadline = ContinuousClock.now + ackTimeout
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if let ack = mailbox.takeAck(id: id) {
                switch ack.result {
                case .inserted:
                    return
                case .failed:
                    throw Failure.rejected(ack.message ?? "The keyboard couldn't type the dictation.")
                }
            }
            try await Task.sleep(for: pollInterval)
        }
        throw Failure.timedOut
    }
}
