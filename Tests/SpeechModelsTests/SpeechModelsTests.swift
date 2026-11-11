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

    @Test func rankingPutsParakeetFirstThenPhonon2ThenWhisper() {
        #expect(SpeechModel.ranked == [.parakeetV2, .phonon2, .whisperSmall])
    }

    @Test func phonon2IsEnglishOnlyAndCredited() {
        #expect(SpeechModel.phonon2.rawValue == "phonon-2")
        #expect(SpeechModel.phonon2.isEnglishOnly)
        #expect(SpeechModel.parakeetV2.isEnglishOnly)
        #expect(!SpeechModel.whisperSmall.isEnglishOnly)
        #expect(SpeechModel.phonon2.source.contains("CC-BY-4.0"))
    }

    @Test func everyPhonon2FileIsPinnedToOneImmutableRevision() throws {
        let revision = "a812a0dfef205660787ef6234317ab79acf4d5d6"
        let files = try Self.manifest().files(for: SpeechModel.phonon2.rawValue)
        #expect(files.count == 18)
        for file in files {
            #expect(file.remotePath == "FluidInference/phonon-2-coreml/resolve/\(revision)/\(file.localPath)")
        }
    }

    @Test func phonon2ManifestHoldsWhatFluidAudioLoads() throws {
        let manifest = try Self.manifest()
        let local = manifest.files(for: SpeechModel.phonon2.rawValue).map(\.localPath)
        for component in ["Preprocessor", "Encoder", "Decoder", "JointDecisionv3"] {
            for part in ["coremldata.bin", "model.mil", "weights/weight.bin"] {
                #expect(local.contains("\(component).mlmodelc/\(part)"), "missing \(component).mlmodelc/\(part)")
            }
        }
        #expect(local.contains("parakeet_vocab.json"))
        #expect(!local.contains { $0.hasPrefix("JointDecision.mlmodelc/") })
        #expect(manifest.totalBytes(for: SpeechModel.phonon2.rawValue) == 357_573_278)
        #expect(manifest.totalBytes(for: SpeechModel.phonon2.rawValue) < manifest.totalBytes(for: SpeechModel.parakeetV2.rawValue))
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
