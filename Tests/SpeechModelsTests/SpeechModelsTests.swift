import DictationCore
import Foundation
import SpeechModels
import Testing
import WhisperTranscription

struct SpeechModelsTests {
    let defaults = UserDefaults(suiteName: "SpeechModelsTests-\(UUID().uuidString)")!

    static func manifest() throws -> ModelManifest {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "scripts/model-manifest.txt")
        return try ModelManifest(text: String(contentsOf: url, encoding: .utf8))
    }

    @Test func rankingPutsParakeetFirstThenWhisper() {
        #expect(SpeechModel.ranked == [.parakeetV2, .whisperSmall])
    }

    @Test func everyModelIsPinnedInTheManifest() throws {
        let manifest = try Self.manifest()
        for model in SpeechModel.allCases {
            #expect(!manifest.files(for: model.rawValue).isEmpty, "\(model.rawValue) missing from manifest")
        }
    }

    @Test func choiceIsUnsetAtFirstLaunch() {
        #expect(ModelChoice(defaults: defaults).selected == nil)
        #expect(ModelChoice(defaults: defaults).needsChoice)
    }

    @Test func choicePersists() {
        ModelChoice(defaults: defaults).choose(.parakeetV2)
        #expect(ModelChoice(defaults: defaults).selected == .parakeetV2)
        ModelChoice(defaults: defaults).choose(.whisperSmall)
        #expect(ModelChoice(defaults: defaults).selected == .whisperSmall)
        #expect(!ModelChoice(defaults: defaults).needsChoice)
    }

    @Test func unknownStoredModelCountsAsUnset() {
        defaults.set("removed-model", forKey: ModelChoice.key)
        #expect(ModelChoice(defaults: defaults).needsChoice)
    }

    @Test func pickerShownOnlyWhenNothingIsChosen() {
        #expect(ModelStartup.decide(choice: nil, installed: []) == .showPicker)
        #expect(ModelStartup.decide(choice: .parakeetV2, installed: []) == .use(.parakeetV2))
        #expect(ModelStartup.decide(choice: .whisperSmall, installed: [.parakeetV2]) == .use(.whisperSmall))
    }

    @Test func existingWhisperDownloadIsKeptWithoutAsking() {
        #expect(ModelStartup.decide(choice: nil, installed: [.whisperSmall]) == .use(.whisperSmall))
    }

    @Test func noModelMeansNoTranscriptionAndNoDownload() async {
        let engine = ActiveTranscriber()
        await #expect(throws: ActiveTranscriber.NoModel.self) { try await engine.prepare() }
        await #expect(throws: ActiveTranscriber.NoModel.self) { _ = try await engine.transcribe([0], language: nil) }
    }

    @Test func switchingEnginesForwardsToTheNewOne() async throws {
        struct Fixed: Transcribing {
            let text: String
            func prepare() async throws {}
            func transcribe(_ samples: [Float], language: String?) async throws -> String { text }
        }
        let engine = ActiveTranscriber()
        await engine.use(Fixed(text: "a"))
        #expect(try await engine.transcribe([0], language: nil) == "a")
        await engine.use(Fixed(text: "b"))
        #expect(try await engine.transcribe([0], language: nil) == "b")
    }
}
