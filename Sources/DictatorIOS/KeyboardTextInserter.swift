import DictationCore
import UIKit

/// TextInserting implementation for a keyboard extension using UITextDocumentProxy.
@MainActor
final class KeyboardTextInserter: TextInserting {
    weak var proxy: UITextDocumentProxy?

    func preflight() throws {
        // Keyboard extensions can insert as long as they have full access if needed,
        // but basic insertText works without it for many cases.
        // Expand with permission checks as needed.
    }

    func insert(_ text: String) async throws {
        proxy?.insertText(text)
    }

    func deleteBackward(_ count: Int) async throws {
        for _ in 0..<count {
            proxy?.deleteBackward()
        }
    }
}
