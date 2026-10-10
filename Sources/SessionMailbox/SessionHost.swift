import DictationCore
import Foundation

/// Applies the keyboard's commands to `DictationController` and publishes host status.
/// Recording and transcription stay in the container app (ADR 0001).
@MainActor
public final class SessionHost {
    public let controller: DictationController
    public let inserter: HandoffInserter
    public private(set) var isArmed = false

    private let mailbox: SessionMailbox
    private let post: (SessionSignal) -> Void
    private let now: () -> TimeInterval

    public init(
        controller: DictationController,
        inserter: HandoffInserter,
        mailbox: SessionMailbox,
        post: @escaping (SessionSignal) -> Void = { $0.post() },
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) {
        self.controller = controller
        self.inserter = inserter
        self.mailbox = mailbox
        self.post = post
        self.now = now
    }

    /// Starts listening. Commands queued before this are dropped: they belong to a dead session.
    public func arm() {
        mailbox.discardCommands()
        mailbox.discardDelivery()
        isArmed = true
        publish()
    }

    public func disarm() {
        isArmed = false
        controller.cancel()
        inserter.commandID = nil
        publish()
    }

    public func drainCommands() {
        guard isArmed else { return }
        for command in mailbox.dequeueCommands() {
            apply(command)
            publish()
        }
    }

    public func publish() {
        let status = HostStatus.live(
            armed: isArmed,
            state: controller.state,
            note: controller.lastError,
            at: now()
        )
        try? mailbox.writeHost(status)
        post(.host)
    }

    private func apply(_ command: DictationCommand) {
        switch command.action {
        case .press:
            guard controller.state == .ready else { return }
            inserter.acceptsWithoutCommand = false
            inserter.commandID = command.id
            controller.hotkeyPressed()
        case .finish:
            // `hotkeyPressed` while recording ends the dictation whether it was a hold or a second tap.
            guard controller.state == .recording else { return }
            controller.hotkeyPressed()
        case .cancel:
            controller.cancel()
            inserter.commandID = nil
        }
    }
}
