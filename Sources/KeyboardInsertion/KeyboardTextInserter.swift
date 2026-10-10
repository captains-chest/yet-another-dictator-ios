import DictationCore
import Foundation

/// The part of `UITextDocumentProxy` the inserter needs, so it can be tested with a fake.
@MainActor
public protocol TextDocumentProxying: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
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
}
#endif

/// `TextInserting` for the keyboard extension. Mirrors the macOS keystroke inserter: inserts in
/// chunks, stops between chunks when the task is cancelled (throwing `CancellationError`), and
/// yields every few chunks so the keyboard stays responsive. Never uses the clipboard.
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
    public var proxy: (any TextDocumentProxying)?

    /// Chunks inserted between yields.
    static let chunksPerYield = 8

    public init(proxy: (any TextDocumentProxying)? = nil) {
        self.proxy = proxy
    }

    public func preflight() throws {
        guard proxy != nil else { throw Failure.noTextField }
    }

    public func insert(_ text: String) async throws {
        for (index, chunk) in TextChunker.chunks(text).enumerated() {
            try await pause(before: index)
            // Re-checked per chunk: the keyboard can be dismissed while a long text is inserted.
            guard let proxy else { throw Failure.noTextField }
            proxy.insertText(chunk)
        }
    }

    public func deleteBackward(_ count: Int) async throws {
        for index in 0..<count {
            try await pause(before: index)
            guard let proxy else { throw Failure.noTextField }
            proxy.deleteBackward()
        }
    }

    private func pause(before index: Int) async throws {
        if Task.isCancelled { throw CancellationError() }
        if index > 0, index.isMultiple(of: Self.chunksPerYield) {
            await Task.yield()
            if Task.isCancelled { throw CancellationError() }
        }
    }
}
