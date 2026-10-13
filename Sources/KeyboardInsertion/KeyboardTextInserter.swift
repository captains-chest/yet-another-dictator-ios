import DictationCore
import Foundation

/// The part of `UITextDocumentProxy` the inserter needs, so it can be tested with a fake.
@MainActor
public protocol TextDocumentProxying: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
    /// The text in front of the cursor, as far as the host app shares it.
    var documentContextBeforeInput: String? { get }
    /// The selected text, if any. `deleteBackward` would remove the selection.
    var selectedText: String? { get }
    /// Changes when the keyboard moves to another text field.
    var documentIdentifier: UUID { get }
}

#if canImport(UIKit)
import UIKit
/// Adapts the keyboard's proxy (a protocol existential) to `TextDocumentProxying`.
@MainActor
public final class UIKitTextDocumentProxy: TextDocumentProxying {
    private let proxy: any UITextDocumentProxy
    public init(_ proxy: any UITextDocumentProxy) { self.proxy = proxy }
    public func insertText(_ text: String) { proxy.insertText(text) }
    public func deleteBackward() { proxy.deleteBackward() }
    public var documentContextBeforeInput: String? { proxy.documentContextBeforeInput }
    public var selectedText: String? { proxy.selectedText }
    public var documentIdentifier: UUID { proxy.documentIdentifier }
}
#endif

/// `TextInserting` for the keyboard extension. Mirrors the macOS keystroke inserter: inserts in
/// chunks, stops between chunks when the task is cancelled (throwing `CancellationError`), and
/// yields every few chunks so the keyboard stays responsive. Never uses the clipboard.
///
/// It also remembers what the last completed insert typed, so Undo Last Dictation can delete
/// exactly that, like the macOS app's dictation history. Anything else forgets it.
@MainActor
public final class KeyboardTextInserter: TextInserting {
    public enum Failure: LocalizedError, Equatable {
        case noTextField

        public var errorDescription: String? {
            "The text field is no longer available, so the dictation couldn't be typed."
        }
    }

    /// The current keyboard's proxy. Set it in `viewWillAppear` and clear it in
    /// `viewWillDisappear`, so text is never inserted after the keyboard is dismissed.
    /// A new proxy means the keyboard appeared again, maybe in another field, so the last
    /// dictation is no longer offered for undo.
    public var proxy: (any TextDocumentProxying)? {
        didSet { lastInsert = nil }
    }

    /// What the last completed insert typed (including any smart-join space), and where.
    private var lastInsert: LastInsert?

    private struct LastInsert {
        let text: String
        let document: UUID
    }

    /// Chunks inserted between yields.
    static let chunksPerYield = 8

    public init(proxy: (any TextDocumentProxying)? = nil) {
        self.proxy = proxy
    }

    public func preflight() throws {
        guard proxy != nil else { throw Failure.noTextField }
    }

    public func insert(_ text: String) async throws {
        lastInsert = nil
        let document = proxy?.documentIdentifier
        for (index, chunk) in TextChunker.chunks(text).enumerated() {
            try await pause(before: index)
            // Re-checked per chunk: the keyboard can be dismissed while a long text is inserted.
            guard let proxy else { throw Failure.noTextField }
            proxy.insertText(chunk)
        }
        // Only a complete insert into one field is undoable. A cancelled or failed one threw above.
        // A CR LF pair is one Character here, but the host may delete it as two, so the count to
        // delete isn't certain: not offered.
        guard let proxy, let document, proxy.documentIdentifier == document,
              !text.isEmpty, !text.contains("\r\n")
        else { return }
        lastInsert = LastInsert(text: text, document: document)
    }

    public func deleteBackward(_ count: Int) async throws {
        lastInsert = nil
        for index in 0..<count {
            try await pause(before: index)
            guard let proxy else { throw Failure.noTextField }
            proxy.deleteBackward()
        }
    }

    /// Whether the last dictation can still be undone: it was typed completely, and the cursor is
    /// still right after it in the same field, with nothing selected. Forgets it as soon as that
    /// stops being true (the user typed, moved the cursor or switched fields), like the macOS app.
    public func checkUndo() -> Bool {
        guard let lastInsert, let proxy,
              proxy.documentIdentifier == lastInsert.document,
              proxy.selectedText?.isEmpty ?? true,
              let before = proxy.documentContextBeforeInput,
              // Compared as Characters, the unit `deleteBackward` removes: a dictation whose first
              // character merged with the one before it doesn't match, and isn't deleted.
              before.suffix(lastInsert.text.count).elementsEqual(lastInsert.text)
        else {
            lastInsert = nil
            return false
        }
        return true
    }

    /// Deletes exactly what the last dictation typed, if `checkUndo()` allows it. Returns whether
    /// it did. Either way the dictation is forgotten, so it can't be undone twice.
    @discardableResult
    public func undoLastInsert() async throws -> Bool {
        guard checkUndo(), let lastInsert else { return false }
        try await deleteBackward(lastInsert.text.count)
        return true
    }

    /// Forgets the last dictation, e.g. when the keyboard goes away.
    public func forgetLastInsert() {
        lastInsert = nil
    }

    private func pause(before index: Int) async throws {
        if Task.isCancelled { throw CancellationError() }
        if index > 0, index.isMultiple(of: Self.chunksPerYield) {
            await Task.yield()
            if Task.isCancelled { throw CancellationError() }
        }
    }
}
