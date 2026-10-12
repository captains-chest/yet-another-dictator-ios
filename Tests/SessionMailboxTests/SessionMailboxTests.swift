import DictationCore
import Foundation
@testable import KeyboardInsertion
@testable import SessionMailbox
import Testing

@MainActor
final class Clock {
    var time: TimeInterval = 1_000
}

@MainActor
final class FakeProxy: TextDocumentProxying {
    var text = ""
    func insertText(_ text: String) { self.text += text }
    func deleteBackward() {
        if !text.isEmpty { text.removeLast() }
    }
}

@MainActor
final class FakeRecorder: AudioRecording {
    var samplesToReturn = [Float](repeating: 0.2, count: 8_000)
    private(set) var isRecording = false

    func start(onLevel: @escaping @Sendable (Float) -> Void) throws {
        isRecording = true
    }

    func stop() -> [Float] {
        isRecording = false
        return samplesToReturn
    }
}

actor FakeTranscriber: Transcribing {
    var result = "hello world"
    func prepare() async throws {}
    func transcribe(_ samples: [Float], language: String?) async throws -> String { result }
    func set(result: String) { self.result = result }
}

@MainActor
struct MailboxTests {
    @Test func commandsDequeueInOrderAndACorruptFileIsDropped() throws {
        let mailbox = try makeMailbox()
        let clock = Clock()
        try mailbox.enqueue(DictationCommand(id: UUID(), action: .press, sequence: 1), at: clock.time)
        try mailbox.enqueue(DictationCommand(id: UUID(), action: .finish, sequence: 2), at: clock.time)
        let garbage = mailbox.directory.appending(path: "commands/0000000000000-00000000.json")
        try Data("nope".utf8).write(to: garbage)

        let actions = mailbox.dequeueCommands().map(\.action)

        #expect(actions == [.press, .finish])
        #expect(mailbox.listCommands().isEmpty)
    }

    @Test func hostAndDeliveryRoundTrip() throws {
        let mailbox = try makeMailbox()
        let status = HostStatus(armed: true, phase: .recording, note: nil, updatedAt: 10)
        try mailbox.writeHost(status)
        #expect(mailbox.readHost() == status)

        let delivery = sampleDelivery(commandID: UUID(), at: 10)
        try mailbox.writeDelivery(delivery)
        #expect(mailbox.peekDelivery() == delivery)
        #expect(mailbox.claimDelivery(id: UUID()) == nil)
        #expect(mailbox.peekDelivery() == delivery)
        #expect(mailbox.claimDelivery(id: delivery.id) == delivery)
        #expect(mailbox.peekDelivery() == nil)
    }

    @Test func acknowledgementForAnotherIdIsDropped() throws {
        let mailbox = try makeMailbox()
        try mailbox.writeAck(DeliveryAck(id: UUID(), result: .inserted, message: nil))
        #expect(mailbox.takeAck(id: UUID()) == nil)
        #expect(mailbox.takeAck(id: UUID()) == nil)
    }
}

@MainActor
struct KeyboardSessionTests {
    @Test func pressDoesNothingUntilTheHostIsFresh() async throws {
        let rig = try Rig()
        rig.keyboard.press()
        #expect(rig.mailbox.listCommands().isEmpty)

        try rig.mailbox.writeHost(HostStatus(armed: true, phase: .ready, note: nil, updatedAt: rig.clock.time - 10))
        await rig.keyboard.refresh()
        #expect(rig.keyboard.phase == .hostUnavailable)
        rig.keyboard.press()
        #expect(rig.mailbox.listCommands().isEmpty)
    }

    @Test func aMissingFieldDoesNotStartDictation() async throws {
        let rig = try Rig(proxy: nil)
        try await rig.becomeReady()
        rig.keyboard.press()
        #expect(rig.mailbox.listCommands().isEmpty)
        #expect(rig.keyboard.banner != nil)
    }

    @Test func tapSendsPressAndHoldSendsFinish() async throws {
        let rig = try Rig()
        try await rig.becomeReady()

        rig.keyboard.press()
        rig.clock.time += 0.1
        rig.keyboard.release()
        #expect(rig.mailbox.listCommands().map(\.action) == [.press])

        let held = try Rig()
        try await held.becomeReady()
        held.keyboard.press()
        held.clock.time += 0.5
        held.keyboard.release()
        #expect(held.mailbox.listCommands().map(\.action) == [.press, .finish])
    }

    @Test func aSecondTapFinishesTheOriginalGesture() async throws {
        let rig = try Rig()
        try await rig.becomeReady()
        rig.keyboard.press()
        let startID = try #require(rig.mailbox.listCommands().first).id
        try rig.mailbox.writeHost(HostStatus(armed: true, phase: .recording, note: nil, updatedAt: rig.clock.time))
        await rig.keyboard.refresh()

        rig.clock.time += 0.1
        rig.keyboard.release()
        rig.keyboard.press()

        #expect(rig.mailbox.listCommands().map(\.action) == [.press, .finish])
        try rig.mailbox.writeDelivery(sampleDelivery(commandID: startID, text: "There.", at: rig.clock.time))
        rig.context.value = "Hello"
        await rig.keyboard.refresh()
        #expect(rig.proxy.text == " there.")
        #expect(rig.mailbox.peekDelivery() == nil)
        #expect(storedAck(rig.mailbox)?.result == .inserted)
    }

    @Test func aTranscriptForAnotherGestureStaysPut() async throws {
        let rig = try Rig()
        try await rig.becomeReady()
        rig.keyboard.press()
        try rig.mailbox.writeDelivery(sampleDelivery(commandID: UUID(), text: "Nope", at: rig.clock.time))
        await rig.keyboard.refresh()
        #expect(rig.proxy.text.isEmpty)
        #expect(rig.mailbox.peekDelivery()?.text == "Nope")
    }

    @Test func anExpiredTranscriptIsDeleted() async throws {
        let rig = try Rig()
        try await rig.becomeReady()
        rig.keyboard.press()
        let startID = try #require(rig.mailbox.listCommands().first).id
        try rig.mailbox.writeDelivery(sampleDelivery(
            commandID: startID,
            text: "Old",
            at: rig.clock.time - KeyboardSession.deliveryLifetime - 1
        ))
        await rig.keyboard.refresh()
        #expect(rig.proxy.text.isEmpty)
        #expect(rig.mailbox.peekDelivery() == nil)
    }

    @Test func aRetryIsTypedWithoutAMatchingGesture() async throws {
        let rig = try Rig()
        try await rig.becomeReady()
        var delivery = sampleDelivery(commandID: UUID(), text: "Retry", at: rig.clock.time)
        delivery.acceptsWithoutCommand = true
        try rig.mailbox.writeDelivery(delivery)
        await rig.keyboard.refresh()
        #expect(rig.proxy.text == "Retry")
    }

    @Test func aFailedInsertIsReported() async throws {
        let rig = try Rig()
        try await rig.becomeReady()
        rig.keyboard.press()
        let startID = try #require(rig.mailbox.listCommands().first).id
        rig.keyboard.inserter.proxy = nil
        try rig.mailbox.writeDelivery(sampleDelivery(commandID: startID, text: "Hello", at: rig.clock.time))
        await rig.keyboard.refresh()
        let ack = try #require(storedAck(rig.mailbox))
        #expect(ack.result == .failed)
        #expect(rig.mailbox.peekDelivery() == nil)
    }
}

@MainActor
struct HandoffTests {
    @Test func insertWaitsUntilTheKeyboardAcknowledges() async throws {
        let rig = try Rig()
        try await rig.becomeReady()
        rig.keyboard.press()
        let startID = try #require(rig.mailbox.listCommands().first).id
        rig.handoff.commandID = startID

        async let typed: Void = rig.handoff.insert("Hello")
        try await Task.sleep(for: .milliseconds(30))
        await rig.keyboard.refresh()
        try await typed

        #expect(rig.proxy.text == "Hello")
    }

    @Test func insertTimesOutWhenNobodyIsListening() async throws {
        let mailbox = try makeMailbox()
        let clock = Clock()
        let handoff = HandoffInserter(
            mailbox: mailbox,
            post: { _ in },
            now: { clock.time },
            ackTimeout: .milliseconds(40),
            pollInterval: .milliseconds(5)
        )
        handoff.commandID = UUID()
        await #expect(throws: HandoffInserter.Failure.timedOut) {
            try await handoff.insert("Hello")
        }
    }

    @Test func aRejectedInsertThrows() async throws {
        let mailbox = try makeMailbox()
        let handoff = HandoffInserter(
            mailbox: mailbox,
            post: { _ in },
            ackTimeout: .seconds(2),
            pollInterval: .milliseconds(5)
        )
        handoff.commandID = UUID()
        let waiter = Task {
            for _ in 0..<50 {
                if let delivery = mailbox.peekDelivery() {
                    try mailbox.writeAck(DeliveryAck(id: delivery.id, result: .failed, message: "No text field."))
                    return
                }
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        await #expect(throws: HandoffInserter.Failure.rejected("No text field.")) {
            try await handoff.insert("Hello")
        }
        try await waiter.value
    }

    @Test func cancellationStopsWaiting() async throws {
        let mailbox = try makeMailbox()
        let handoff = HandoffInserter(
            mailbox: mailbox,
            post: { _ in },
            ackTimeout: .seconds(5),
            pollInterval: .milliseconds(5)
        )
        handoff.commandID = UUID()
        let task = Task { try await handoff.insert("Hello") }
        try await Task.sleep(for: .milliseconds(15))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

@MainActor
struct SessionHostTests {
    @Test func armDropsCommandsFromADeadSession() async throws {
        let rig = try Pipeline()
        try rig.mailbox.enqueue(DictationCommand(id: UUID(), action: .press, sequence: 1), at: 1)
        await rig.controller.loadModel()
        rig.host.arm()
        #expect(rig.mailbox.listCommands().isEmpty)
        rig.host.drainCommands()
        #expect(rig.controller.state == .ready)
    }

    @Test func aQueuedHoldStillTranscribes() async throws {
        let rig = try Pipeline()
        await rig.controller.loadModel()
        rig.host.arm()
        await rig.keyboard.refresh()
        rig.keyboard.press()
        rig.clock.time += 1
        rig.keyboard.release()

        rig.host.drainCommands()
        for _ in 0..<30 {
            await rig.keyboard.refresh()
            if rig.controller.state == .ready, !rig.proxy.text.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(rig.proxy.text == "hello world")
        #expect(rig.controller.state == .ready)
        #expect(rig.mailbox.peekDelivery() == nil)
    }

    @Test func cancelStopsRecording() async throws {
        let rig = try Pipeline()
        await rig.controller.loadModel()
        rig.host.arm()
        await rig.keyboard.refresh()
        rig.keyboard.press()
        rig.host.drainCommands()
        #expect(rig.controller.state == .recording)

        rig.keyboard.cancel()
        rig.host.drainCommands()
        #expect(rig.controller.state == .ready)
        #expect(rig.recorder.isRecording == false)
        #expect(rig.proxy.text.isEmpty)
    }

    /// P0: the container must not SmartJoin from its own history before the keyboard joins from
    /// `documentContextBeforeInput`. A field that already ends with a space makes a double join
    /// visible as two spaces (and wrong capitalization) on the second consecutive dictation.
    @Test func consecutiveDictationsAreJoinedOnlyByTheKeyboard() async throws {
        let rig = try Pipeline()
        await rig.controller.loadModel()
        rig.host.arm()
        try await rig.mailbox.writeHost(HostStatus(armed: true, phase: .ready, note: nil, updatedAt: rig.clock.time))
        await rig.keyboard.refresh()

        // Mid-sentence field that already has the separating space.
        rig.context.value = "Hello "
        try await rig.dictate("World.")
        #expect(rig.proxy.text == "world.")
        #expect(rig.controller.state == .ready)

        // Keep the same preceding text: if the controller had pre-joined against history
        // ("World." → " Again."), the keyboard would keep that leading space and we'd get
        // "world. Again." with a double space once this is pasted after "Hello ".
        rig.context.value = "Hello "
        try await rig.dictate("Again.")
        #expect(rig.proxy.text == "world.again.")
        #expect(rig.mailbox.peekDelivery() == nil)
    }
}

@MainActor
struct ProjectLayoutTests {
    @Test func entitlementsAndKeyboardPlistMatchTheHandoff() throws {
        let root = repoRoot()
        let app = try String(contentsOf: root.appending(path: "App/Dictator.entitlements"), encoding: .utf8)
        let keyboard = try String(contentsOf: root.appending(path: "Keyboard/Keyboard.entitlements"), encoding: .utf8)
        let info = try String(contentsOf: root.appending(path: "Keyboard/Info.plist"), encoding: .utf8)
        let appInfo = try String(contentsOf: root.appending(path: "App/Info.plist"), encoding: .utf8)

        #expect(app.contains(AppGroup.identifier))
        #expect(keyboard.contains(AppGroup.identifier))
        #expect(info.contains("<key>RequestsOpenAccess</key>"))
        #expect(info.contains("<true/>"))
        #expect(appInfo.contains("NSMicrophoneUsageDescription"))
        #expect(appInfo.contains("<string>audio</string>"))
    }
}

@MainActor
private final class ContextBox {
    var value: String?
}

@MainActor
private final class Rig {
    let clock: Clock
    let mailbox: SessionMailbox
    let proxy: FakeProxy
    let handoff: HandoffInserter
    let keyboard: KeyboardSession
    let context: ContextBox

    init(proxy attached: FakeProxy? = FakeProxy()) throws {
        let clock = Clock()
        let context = ContextBox()
        let mailbox = try makeMailbox()
        let proxy = attached ?? FakeProxy()
        self.clock = clock
        self.context = context
        self.mailbox = mailbox
        self.proxy = proxy
        handoff = HandoffInserter(
            mailbox: mailbox,
            post: { _ in },
            now: { clock.time },
            ackTimeout: .seconds(2),
            pollInterval: .milliseconds(5)
        )
        keyboard = KeyboardSession(
            mailbox: mailbox,
            inserter: KeyboardTextInserter(proxy: attached),
            post: { _ in },
            now: { clock.time },
            contextBeforeCursor: { context.value }
        )
    }

    func becomeReady() async throws {
        try mailbox.writeHost(HostStatus(armed: true, phase: .ready, note: nil, updatedAt: clock.time))
        await keyboard.refresh()
        #expect(keyboard.phase == .ready)
    }
}

@MainActor
private final class Pipeline {
    let clock: Clock
    let mailbox: SessionMailbox
    let proxy: FakeProxy
    let recorder: FakeRecorder
    let transcriber: FakeTranscriber
    let controller: DictationController
    let host: SessionHost
    let keyboard: KeyboardSession
    let context: ContextBox

    init() throws {
        let clock = Clock()
        let context = ContextBox()
        let mailbox = try makeMailbox()
        let proxy = FakeProxy()
        let recorder = FakeRecorder()
        let transcriber = FakeTranscriber()
        self.clock = clock
        self.context = context
        self.mailbox = mailbox
        self.proxy = proxy
        self.recorder = recorder
        self.transcriber = transcriber
        let handoff = HandoffInserter(
            mailbox: mailbox,
            post: { _ in },
            now: { clock.time },
            ackTimeout: .seconds(2),
            pollInterval: .milliseconds(10)
        )
        let controller = DictationController(
            recorder: recorder,
            transcriber: transcriber,
            inserter: handoff,
            precedingText: NoPrecedingText(),
            now: { clock.time },
            stopTail: .zero,
            transcriptionTimeout: { _ in .seconds(5) },
            containsSpeech: { _ in true }
        )
        self.controller = controller
        host = SessionHost(
            controller: controller,
            inserter: handoff,
            mailbox: mailbox,
            post: { _ in },
            now: { clock.time }
        )
        keyboard = KeyboardSession(
            mailbox: mailbox,
            inserter: KeyboardTextInserter(proxy: proxy),
            post: { _ in },
            now: { clock.time },
            contextBeforeCursor: { context.value }
        )
    }

    /// Hold-to-talk one utterance and wait until the keyboard has typed it (or we time out).
    func dictate(_ transcript: String) async throws {
        await transcriber.set(result: transcript)
        host.publish()
        await keyboard.refresh()
        keyboard.press()
        clock.time += 1
        keyboard.release()
        host.drainCommands()
        for _ in 0..<50 {
            host.publish()
            await keyboard.refresh()
            if controller.state == .ready, mailbox.peekDelivery() == nil { return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

@MainActor
private func makeMailbox() throws -> SessionMailbox {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "mailbox-\(UUID().uuidString)", directoryHint: .isDirectory)
    return try SessionMailbox(directory: directory)
}

private func sampleDelivery(
    commandID: UUID,
    text: String = "Hello",
    at time: TimeInterval
) -> DictationDelivery {
    DictationDelivery(
        id: UUID(),
        commandID: commandID,
        text: text,
        deleteCount: nil,
        acceptsWithoutCommand: false,
        createdAt: time
    )
}

@MainActor
private func storedAck(_ mailbox: SessionMailbox) -> DeliveryAck? {
    let url = mailbox.directory.appending(path: "ack.json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(DeliveryAck.self, from: data)
}

private func repoRoot() -> URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
