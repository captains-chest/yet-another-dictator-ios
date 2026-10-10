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

    /// ADR 0003: every file the transcriber refuses to fetch must be pinned in the manifest.
    @Test func manifestCoversEveryRequiredFile() throws {
        let manifest = try String(contentsOf: Self.repoRoot.appending(path: "scripts/model-manifest.txt"), encoding: .utf8)
        let paths = manifest.split(separator: "\n").compactMap { line -> String? in
            guard !line.hasPrefix("#") else { return nil }
            let parts = line.split(separator: " ")
            guard parts.count == 3 else { return nil }
            return String(parts[2])
        }
        for required in WhisperKitTranscriber.requiredFiles {
            #expect(
                paths.contains { $0 == required || $0.hasPrefix(required + "/") },
                "manifest is missing \(required)"
            )
        }
    }
}
