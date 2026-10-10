import DictationCore
import Foundation

/// Shared container for the in-flight transcript. Both targets use the same identifier in their
/// entitlements. The container holds commands and one transcript, never audio and never a history.
public enum AppGroup {
    public static let identifier = "group.com.captainduckay.dictator.ios"

    /// Nil when the entitlement is missing, or when the keyboard has not been given Full Access.
    public static func containerURL(fileManager: FileManager = .default) -> URL? {
        #if os(iOS) || os(macOS) || os(visionOS)
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        #else
        nil
        #endif
    }
}

public enum SessionSignal: String, Sendable {
    case command = "com.captainduckay.dictator.ios.command"
    case host = "com.captainduckay.dictator.ios.host"
    case delivery = "com.captainduckay.dictator.ios.delivery"
    case acknowledgment = "com.captainduckay.dictator.ios.ack"

    public func post() {
        #if os(iOS) || os(macOS) || os(visionOS)
        DarwinSessionCenter.shared.post(self)
        #endif
    }
}

/// What the keyboard asks the app to do. The keyboard decides tap versus hold, because the app
/// may apply both messages in one turn and `DictationController` would then see no time pass.
/// A tap sends `press` and stays recording until the next `finish`. A hold sends `finish` on release.
public struct DictationCommand: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        case press
        case finish
        case cancel
    }

    public var id: UUID
    public var action: Action
    /// Orders two commands written in the same millisecond. Unique per keyboard process.
    public var sequence: UInt64

    public init(id: UUID, action: Action, sequence: UInt64) {
        self.id = id
        self.action = action
        self.sequence = sequence
    }
}

/// The latest transcript (or a deletion) waiting for the keyboard. Replaced, never appended.
public struct DictationDelivery: Codable, Equatable, Sendable {
    public var id: UUID
    /// The `press` that started this dictation. The keyboard ignores a transcript for a gesture
    /// it does not have in flight, unless `acceptsWithoutCommand` is set (a retry from the app).
    public var commandID: UUID
    /// Cleaned transcript, not yet fitted to the field. The keyboard applies smart spacing.
    public var text: String
    /// When set, delete this many characters instead of inserting `text`.
    public var deleteCount: Int?
    /// The keyboard should type this even if it did not start the gesture. Used for retry.
    public var acceptsWithoutCommand: Bool
    public var createdAt: TimeInterval

    public init(
        id: UUID,
        commandID: UUID,
        text: String,
        deleteCount: Int?,
        acceptsWithoutCommand: Bool,
        createdAt: TimeInterval
    ) {
        self.id = id
        self.commandID = commandID
        self.text = text
        self.deleteCount = deleteCount
        self.acceptsWithoutCommand = acceptsWithoutCommand
        self.createdAt = createdAt
    }
}

public struct DeliveryAck: Codable, Equatable, Sendable {
    public enum Result: String, Codable, Sendable {
        case inserted
        case failed
    }

    public var id: UUID
    public var result: Result
    public var message: String?

    public init(id: UUID, result: Result, message: String?) {
        self.id = id
        self.result = result
        self.message = message
    }
}

public enum HostPhase: String, Codable, Equatable, Sendable {
    case loadingModel
    case ready
    case recording
    case transcribing
    case unavailable
}

/// Whether the app is awake and what the dictation is doing. No transcript.
public struct HostStatus: Codable, Equatable, Sendable {
    public var armed: Bool
    public var phase: HostPhase
    /// User-facing status (a model failure, or the last microphone error). Never a transcript.
    public var note: String?
    public var updatedAt: TimeInterval

    public init(armed: Bool, phase: HostPhase, note: String?, updatedAt: TimeInterval) {
        self.armed = armed
        self.phase = phase
        self.note = note
        self.updatedAt = updatedAt
    }

    public static func live(
        armed: Bool,
        state: DictationState,
        note: String?,
        at time: TimeInterval
    ) -> HostStatus {
        switch state {
        case .loadingModel:
            return HostStatus(armed: armed, phase: .loadingModel, note: note, updatedAt: time)
        case .ready:
            return HostStatus(armed: armed, phase: .ready, note: note, updatedAt: time)
        case .recording:
            return HostStatus(armed: armed, phase: .recording, note: note, updatedAt: time)
        case .transcribing:
            return HostStatus(armed: armed, phase: .transcribing, note: note, updatedAt: time)
        case .unavailable(let message):
            return HostStatus(armed: armed, phase: .unavailable, note: message, updatedAt: time)
        }
    }
}
