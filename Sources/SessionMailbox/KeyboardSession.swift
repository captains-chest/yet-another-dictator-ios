import DictationCore
import Foundation
import KeyboardInsertion
import Observation

public enum KeyboardPhase: Equatable, Sendable {
    case hostUnavailable
    case loadingModel
    case ready
    case recording
    case transcribing
    case unavailable(String)
}

/// The keyboard's side of a dictation: forwards the mic gesture, and types a transcript when one
/// arrives. Smart spacing uses the field in front of the cursor, which only this process can see.
@MainActor
@Observable
public final class KeyboardSession {
    /// Host heartbeats older than this mean the app is suspended or not armed.
    public static let hostStaleAfter: TimeInterval = 3
    /// Ready polls with the press already consumed before the gesture is treated as declined.
    private static let readyPollsBeforeGivingUp = 3
    /// A transcript older than this is dropped. Covers the 10-minute capture cap plus transcription.
    public static let deliveryLifetime: TimeInterval = 15 * 60

    /// Same default as `DictationController`. The keyboard applies it, so a queued hold still ends.
    public static let holdThreshold: TimeInterval = 0.35

    public private(set) var phase: KeyboardPhase = .hostUnavailable
    /// A short, user-facing problem. Never a transcript.
    public private(set) var banner: String?
    /// Whether Undo Last Dictation is offered: the last transcript was typed completely and nothing
    /// has changed in front of the cursor since. Updated on every `refresh()`.
    public private(set) var canUndo = false
    public let inserter: KeyboardTextInserter

    private let mailbox: SessionMailbox
    private let post: (SessionSignal) -> Void
    private let now: () -> TimeInterval
    private let contextBeforeCursor: () -> String?
    private var sequence: UInt64 = 0
    private var activeCommandID: UUID?
    private var pressedAt: TimeInterval?
    /// True once the app has reported this gesture as recording or transcribing.
    private var sawBusy = false
    /// Ready polls after the app has already taken the press and stayed ready. A single poll can
    /// land in the gap between dequeue and publish, so the gesture is abandoned only after a few.
    private var ignoredReadyPolls = 0
    private var isDelivering = false

    public init(
        mailbox: SessionMailbox,
        inserter: KeyboardTextInserter,
        post: @escaping (SessionSignal) -> Void = { $0.post() },
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
        contextBeforeCursor: @escaping () -> String? = { nil }
    ) {
        self.mailbox = mailbox
        self.inserter = inserter
        self.post = post
        self.now = now
        self.contextBeforeCursor = contextBeforeCursor
    }

    public var canDictate: Bool {
        switch phase {
        case .ready, .recording: true
        case .hostUnavailable, .loadingModel, .transcribing, .unavailable: false
        }
    }

    public func press() {
        if phase == .recording {
            finishGesture()
            return
        }
        // Ignore a second tap until the app has acknowledged the first one.
        guard phase == .ready, activeCommandID == nil else { return }
        do {
            try inserter.preflight()
            let command = nextCommand(.press)
            try mailbox.enqueue(command, at: now())
            activeCommandID = command.id
            sawBusy = false
        } catch {
            activeCommandID = nil
            banner = error.localizedDescription
            return
        }
        pressedAt = now()
        banner = nil
        phase = .recording
        post(.command)
    }

    public func release() {
        guard let pressedAt else { return }
        let held = now() - pressedAt >= Self.holdThreshold
        self.pressedAt = nil
        // A short tap leaves recording on. The next press sends `finish`.
        guard held else { return }
        finishGesture()
    }

    public func cancel() {
        clearGesture()
        do {
            try mailbox.enqueue(nextCommand(.cancel), at: now())
        } catch {
            return
        }
        post(.command)
    }

    private func finishGesture() {
        pressedAt = nil
        do {
            try mailbox.enqueue(nextCommand(.finish), at: now())
        } catch {
            banner = error.localizedDescription
            return
        }
        phase = .transcribing
        post(.command)
    }

    /// Reads the host and types a waiting transcript. Call on a timer and whenever a signal arrives.
    public func refresh() async {
        defer { updateUndo() }
        let timestamp = now()
        if !isDelivering, let delivery = mailbox.peekDelivery() {
            isDelivering = true
            await handle(delivery, now: timestamp)
            isDelivering = false
        }
        guard let host = mailbox.readHost(), host.armed, timestamp - host.updatedAt <= Self.hostStaleAfter else {
            phase = .hostUnavailable
            return
        }
        switch host.phase {
        case .loadingModel:
            phase = .loadingModel
        case .ready:
            let ours = mailbox.peekDelivery()?.commandID == activeCommandID && activeCommandID != nil
            if sawBusy && !ours {
                clearGesture()
            } else if let activeCommandID, !sawBusy {
                let stillQueued = mailbox.listCommands().contains { $0.id == activeCommandID && $0.action == .press }
                if stillQueued {
                    ignoredReadyPolls = 0
                } else {
                    ignoredReadyPolls += 1
                    if ignoredReadyPolls >= Self.readyPollsBeforeGivingUp { clearGesture() }
                }
            } else {
                ignoredReadyPolls = 0
            }
            if activeCommandID == nil {
                phase = .ready
                banner = host.note
            }
        case .recording:
            sawBusy = true
            ignoredReadyPolls = 0
            phase = .recording
        case .transcribing:
            sawBusy = true
            ignoredReadyPolls = 0
            phase = .transcribing
        case .unavailable:
            clearGesture()
            phase = .unavailable(host.note ?? "Dictation is unavailable.")
        }
    }

    /// Deletes exactly what the last transcript typed (including any smart-join space), if the
    /// field still ends with it. Purely local: the app isn't involved.
    public func undo() async {
        guard canUndo, !isDelivering else { return }
        canUndo = false
        do {
            try await inserter.undoLastInsert()
        } catch is CancellationError {
            return
        } catch {
            banner = error.localizedDescription
        }
    }

    private func updateUndo() {
        // Only checked while idle; the check forgets the dictation if the field changed.
        canUndo = phase == .ready && activeCommandID == nil && !isDelivering && inserter.checkUndo()
    }

    private func clearGesture() {
        activeCommandID = nil
        sawBusy = false
        pressedAt = nil
        ignoredReadyPolls = 0
    }

    private func handle(_ delivery: DictationDelivery, now timestamp: TimeInterval) async {
        guard timestamp - delivery.createdAt <= Self.deliveryLifetime else {
            mailbox.removeDelivery(id: delivery.id)
            if delivery.commandID == activeCommandID { clearGesture() }
            return
        }
        let matches = delivery.commandID == activeCommandID
        guard matches || delivery.acceptsWithoutCommand else { return }
        guard mailbox.claimDelivery(id: delivery.id) != nil else { return }
        do {
            if let count = delivery.deleteCount {
                if count > 0 { try await inserter.deleteBackward(count) }
            } else if !delivery.text.isEmpty {
                let typed = SmartJoin.adjust(delivery.text, after: contextBeforeCursor())
                try await inserter.insert(typed)
            }
            try mailbox.writeAck(DeliveryAck(id: delivery.id, result: .inserted, message: nil))
            if matches { activeCommandID = nil }
        } catch is CancellationError {
            return
        } catch {
            try? mailbox.writeAck(DeliveryAck(
                id: delivery.id,
                result: .failed,
                message: error.localizedDescription
            ))
        }
        post(.acknowledgment)
    }

    private func nextCommand(_ action: DictationCommand.Action) -> DictationCommand {
        sequence += 1
        return DictationCommand(id: UUID(), action: action, sequence: sequence)
    }
}
