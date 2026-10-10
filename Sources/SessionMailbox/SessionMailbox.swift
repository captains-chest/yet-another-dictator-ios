import Foundation

/// Files in the App Group container. Commands are a queue so a fast tap can't overwrite its own
/// press. The transcript is a single file, deleted when the keyboard claims it.
public struct SessionMailbox: Sendable {
    public let directory: URL
    private let commandsDirectory: URL
    private let hostURL: URL
    private let deliveryURL: URL
    private let acknowledgmentURL: URL

    public init(directory: URL) throws {
        self.directory = directory
        commandsDirectory = directory.appending(path: "commands", directoryHint: .isDirectory)
        hostURL = directory.appending(path: "host.json")
        deliveryURL = directory.appending(path: "delivery.json")
        acknowledgmentURL = directory.appending(path: "ack.json")
        try FileManager.default.createDirectory(at: commandsDirectory, withIntermediateDirectories: true)
    }

    // MARK: Commands

    public func enqueue(_ command: DictationCommand, at time: TimeInterval) throws {
        let millis = UInt64((time * 1000).rounded())
        let name = String(format: "%013llu-%08llu.json", millis, command.sequence)
        let url = commandsDirectory.appending(path: name)
        try write(command, to: url)
    }

    /// Commands in the order they were enqueued. Does not remove them.
    public func listCommands() -> [DictationCommand] {
        commandFiles().compactMap(decodeCommand)
    }

    /// Reads and removes every queued command, in order. An unreadable file is dropped so one
    /// bad write can't stall dictation.
    public func dequeueCommands() -> [DictationCommand] {
        commandFiles().compactMap { url in
            let command = decodeCommand(url)
            try? FileManager.default.removeItem(at: url)
            return command
        }
    }

    public func discardCommands() {
        for url in commandFiles() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Host

    public func writeHost(_ status: HostStatus) throws {
        try write(status, to: hostURL)
    }

    public func readHost() -> HostStatus? {
        decode(HostStatus.self, from: hostURL)
    }

    // MARK: Delivery

    public func writeDelivery(_ delivery: DictationDelivery) throws {
        try write(delivery, to: deliveryURL)
    }

    public func peekDelivery() -> DictationDelivery? {
        decode(DictationDelivery.self, from: deliveryURL)
    }

    /// Removes the delivery only when its id matches, so a newer one isn't discarded by a stale read.
    @discardableResult
    public func claimDelivery(id: UUID) -> DictationDelivery? {
        guard let delivery = peekDelivery(), delivery.id == id else { return nil }
        try? FileManager.default.removeItem(at: deliveryURL)
        return delivery
    }

    public func removeDelivery(id: UUID) {
        guard peekDelivery()?.id == id else { return }
        try? FileManager.default.removeItem(at: deliveryURL)
    }

    public func discardDelivery() {
        try? FileManager.default.removeItem(at: deliveryURL)
    }

    // MARK: Acknowledgement

    public func writeAck(_ ack: DeliveryAck) throws {
        try write(ack, to: acknowledgmentURL)
    }

    /// Removes the acknowledgement when it is for `id`. A stale one is dropped.
    public func takeAck(id: UUID) -> DeliveryAck? {
        guard let ack = decode(DeliveryAck.self, from: acknowledgmentURL) else { return nil }
        try? FileManager.default.removeItem(at: acknowledgmentURL)
        return ack.id == id ? ack : nil
    }

    // MARK: Files

    private func commandFiles() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: commandsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func decodeCommand(_ url: URL) -> DictationCommand? {
        decode(DictationCommand.self, from: url)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try writeAtomically(JSONEncoder().encode(value), to: url)
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporary) }
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }
}
