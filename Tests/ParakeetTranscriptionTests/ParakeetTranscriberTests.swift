import Foundation
import Testing
@testable import ParakeetTranscription

struct ParakeetTranscriberTests {
    func missingFiles(_ variant: ParakeetTranscriber.Variant) async -> [String]? {
        let folder = FileManager.default.temporaryDirectory.appending(path: "parakeet-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try await ParakeetTranscriber(modelFolder: folder, variant: variant).prepare()
            return nil
        } catch ParakeetTranscriber.Failure.missingModelFiles(let files) {
            return files
        } catch {
            return nil
        }
    }

    @Test func incompleteFolderIsRefusedBeforeLoading() async {
        let missing = await missingFiles(.parakeetV2)
        #expect(missing?.contains("JointDecision.mlmodelc") == true)
        #expect(missing?.contains("parakeet_vocab.json") == true)
        #expect(ParakeetTranscriber.requiredFiles == ParakeetTranscriber.Variant.parakeetV2.requiredFiles)
    }

    @Test func phonon2FolderNeedsTheV3Joint() async {
        let missing = await missingFiles(.phonon2)
        #expect(missing?.contains("JointDecisionv3.mlmodelc") == true)
        #expect(missing?.contains("JointDecision.mlmodelc") == false)
        #expect(missing?.contains("parakeet_vocab.json") == true)
    }
}
