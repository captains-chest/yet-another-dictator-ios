import DictationCore
import Foundation
import Testing
import WhisperTranscription

struct WhisperKitTranscriberTests {
    private static var repoRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func refusesToLoadIncompleteModelFolder() async throws {
        let empty = FileManager.default.temporaryDirectory.appending(path: "model-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }

        await #expect(throws: WhisperKitTranscriber.Failure.self) {
            try await WhisperKitTranscriber(modelFolder: empty).prepare()
        }
    }

    /// ADR 0004: every file the transcriber refuses to fetch must be pinned in the manifest.
    @Test func manifestCoversEveryRequiredFile() throws {
        let text = try String(contentsOf: Self.repoRoot.appending(path: "scripts/model-manifest.txt"), encoding: .utf8)
        let paths = try ModelManifest(text: text).files(for: "openai_whisper-small_216MB").map(\.localPath)
        for required in WhisperKitTranscriber.requiredFiles {
            #expect(
                paths.contains { $0 == required || $0.hasPrefix(required + "/") },
                "manifest is missing \(required)"
            )
        }
    }
}
