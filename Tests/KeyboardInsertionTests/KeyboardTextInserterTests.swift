import DictationCore
@testable import KeyboardInsertion
import Testing

@MainActor
final class FakeProxy: TextDocumentProxying {
    var text = ""
    var insertCalls: [String] = []
    /// Called after every insert, e.g. to cancel or drop the proxy mid-way.
    var afterInsert: ((FakeProxy) -> Void)?

    func insertText(_ text: String) {
        insertCalls.append(text)
        self.text += text
        afterInsert?(self)
    }

    func deleteBackward() {
        if !text.isEmpty { text.removeLast() }
    }
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
