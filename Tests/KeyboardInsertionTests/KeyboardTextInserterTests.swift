import DictationCore
import Foundation
@testable import KeyboardInsertion
import Testing

@MainActor
final class FakeProxy: TextDocumentProxying {
    /// Everything before the cursor (the cursor is always at the end).
    var text = ""
    var insertCalls: [String] = []
    var deleteCount = 0
    var selectedText: String?
    var documentIdentifier = UUID()
    /// Called after every insert, e.g. to cancel or drop the proxy mid-way.
    var afterInsert: ((FakeProxy) -> Void)?

    func insertText(_ text: String) {
        insertCalls.append(text)
        self.text += text
        afterInsert?(self)
    }

    func deleteBackward() {
        deleteCount += 1
        if !text.isEmpty { text.removeLast() }
    }

    var documentContextBeforeInput: String? { text }
}

@MainActor
struct KeyboardTextInserterTests {
    @Test func insertsInChunksThatAddUpToTheText() async throws {
        let proxy = FakeProxy()
        let inserter = KeyboardTextInserter(proxy: proxy)
        let text = String(repeating: "Hej verden, dette er en test. ", count: 20) + "😀👍🏽"
        try await inserter.insert(text)
        #expect(proxy.text == text)
        #expect(proxy.insertCalls.count > 1)
        #expect(proxy.insertCalls.allSatisfy { $0.utf16.count <= TextChunker.maxUTF16PerEvent })
    }

    @Test func throwsInsteadOfDroppingTextWithoutAProxy() async {
        let inserter = KeyboardTextInserter()
        #expect(throws: KeyboardTextInserter.Failure.noTextField) { try inserter.preflight() }
        await #expect(throws: KeyboardTextInserter.Failure.noTextField) { try await inserter.insert("hello") }
        await #expect(throws: KeyboardTextInserter.Failure.noTextField) { try await inserter.deleteBackward(1) }
    }

    @Test func throwsWhenTheProxyGoesAwayMidInsert() async {
        let proxy = FakeProxy()
        let inserter = KeyboardTextInserter(proxy: proxy)
        proxy.afterInsert = { _ in inserter.proxy = nil } // the keyboard is dismissed
        await #expect(throws: KeyboardTextInserter.Failure.noTextField) {
            try await inserter.insert(String(repeating: "a", count: 100))
        }
        #expect(proxy.insertCalls.count == 1)
    }

    @Test func cancellationStopsBetweenChunks() async {
        let proxy = FakeProxy()
        let inserter = KeyboardTextInserter(proxy: proxy)
        let text = String(repeating: "word ", count: 200) // 50 chunks
        let task = Task { @MainActor in try await inserter.insert(text) }
        proxy.afterInsert = { proxy in if proxy.insertCalls.count == 3 { task.cancel() } }
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(proxy.insertCalls.count == 3)
    }

    @Test func alreadyCancelledInsertsNothing() async {
        let proxy = FakeProxy()
        let inserter = KeyboardTextInserter(proxy: proxy)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await inserter.insert("hello")
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(proxy.insertCalls.isEmpty)
    }

    @Test func deleteBackwardDeletesExactlyCount() async throws {
        let proxy = FakeProxy()
        proxy.text = "Hello world"
        let inserter = KeyboardTextInserter(proxy: proxy)
        try await inserter.deleteBackward(6)
        #expect(proxy.text == "Hello")
    }
}

@MainActor
struct UndoLastDictationTests {
    @Test func undoAfterInsertRestoresTheText() async throws {
        let proxy = FakeProxy()
        proxy.text = "Note:"
        let inserter = KeyboardTextInserter(proxy: proxy)
        try await inserter.insert(" buy milk and eggs.")
        #expect(inserter.checkUndo())

        #expect(try await inserter.undoLastInsert())
        #expect(proxy.text == "Note:")
        #expect(!inserter.checkUndo())
        #expect(try await !inserter.undoLastInsert())
        #expect(proxy.text == "Note:")
    }

    @Test func refusedWhenTheUserTypedAfter() async throws {
        let proxy = FakeProxy()
        let inserter = KeyboardTextInserter(proxy: proxy)
        try await inserter.insert("Hello there.")
        proxy.text += "!" // typed with another keyboard, or pasted
        #expect(!inserter.checkUndo())
        // Forgotten, even once the field ends with the dictation again.
        proxy.text.removeLast()
        #expect(try await !inserter.undoLastInsert())
        #expect(proxy.text == "Hello there.")
        #expect(proxy.deleteCount == 0)
    }

    @Test func deletesOneCharacterPerEmojiAndCombiningSequence() async throws {
        let proxy = FakeProxy()
        proxy.text = "Før:"
        let inserter = KeyboardTextInserter(proxy: proxy)
        let typed = " Hej 👨‍👩‍👧 🇩🇰 👍🏽 cafe\u{301}"
        try await inserter.insert(typed)
        #expect(try await inserter.undoLastInsert())
        #expect(proxy.text == "Før:")
        #expect(proxy.deleteCount == typed.count)
        #expect(proxy.deleteCount == 15)
    }

    @Test func removesTheSmartJoinSpaceToo() async throws {
        let proxy = FakeProxy()
        proxy.text = "Hello"
        let inserter = KeyboardTextInserter(proxy: proxy)
        let typed = SmartJoin.adjust("There.", after: proxy.documentContextBeforeInput)
        #expect(typed == " there.")
        try await inserter.insert(typed)
        #expect(try await inserter.undoLastInsert())
        #expect(proxy.text == "Hello")
    }

    @Test func aCancelledInsertIsNotUndoable() async throws {
        let proxy = FakeProxy()
        proxy.text = "Keep"
        let inserter = KeyboardTextInserter(proxy: proxy)
        let task = Task { @MainActor in try await inserter.insert(String(repeating: "word ", count: 200)) }
        proxy.afterInsert = { proxy in if proxy.insertCalls.count == 3 { task.cancel() } }
        _ = await task.result
        let partial = proxy.text
        #expect(!inserter.checkUndo())
        #expect(try await !inserter.undoLastInsert())
        #expect(proxy.text == partial)
    }

    @Test func aNewInsertReplacesTheOneToUndo() async throws {
        let proxy = FakeProxy()
        let inserter = KeyboardTextInserter(proxy: proxy)
        try await inserter.insert("One.")
        try await inserter.insert(" Two.")
        #expect(try await inserter.undoLastInsert())
        #expect(proxy.text == "One.")
        #expect(!inserter.checkUndo())
    }

    @Test func refusedInAnotherFieldWithASelectionOrAfterTheKeyboardReappears() async throws {
        let proxy = FakeProxy()
        let inserter = KeyboardTextInserter(proxy: proxy)

        try await inserter.insert("Hello")
        proxy.documentIdentifier = UUID()
        #expect(!inserter.checkUndo())

        try await inserter.insert(" world")
        proxy.selectedText = "world"
        #expect(!inserter.checkUndo())
        proxy.selectedText = nil

        try await inserter.insert(" again")
        inserter.proxy = proxy // the keyboard appeared again
        #expect(!inserter.checkUndo())

        try await inserter.insert(" and")
        try await inserter.deleteBackward(1) // e.g. a delete hand-off from the app
        #expect(!inserter.checkUndo())
        #expect(proxy.text == "Hello world again an")
    }

    @Test func notOfferedWhenTheCountToDeleteIsUncertain() async throws {
        let proxy = FakeProxy()
        let inserter = KeyboardTextInserter(proxy: proxy)
        try await inserter.insert("Line one\r\nLine two")
        #expect(!inserter.checkUndo())

        // A first character that merges with the one before it (here a combining accent).
        proxy.text = "e"
        try await inserter.insert("\u{301} ok")
        #expect(!inserter.checkUndo())
        #expect(proxy.text == "e\u{301} ok")
    }

    @Test func refusedWhenTheHostDoesNotShareTheTextBeforeTheCursor() async throws {
        let proxy = ContextlessProxy()
        let inserter = KeyboardTextInserter(proxy: proxy)
        try await inserter.insert("Secret")
        #expect(!inserter.checkUndo())
        #expect(try await !inserter.undoLastInsert())
        #expect(proxy.deleted == 0)
    }
}

@MainActor
private final class ContextlessProxy: TextDocumentProxying {
    var deleted = 0
    func insertText(_ text: String) {}
    func deleteBackward() { deleted += 1 }
    var documentContextBeforeInput: String? { nil }
    var selectedText: String? { nil }
    let documentIdentifier = UUID()
}
