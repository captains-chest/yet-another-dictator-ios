import DictationCore
import Foundation

/// The speech models Dictator can download, best first. Nothing is downloaded until the user picks
/// one (ADR 0005). Each raw value is the model-id in `model-manifest.txt`.
public enum SpeechModel: String, CaseIterable, Identifiable, Sendable {
    // Declaration order is the ranking shown in the picker: best first.
    case parakeetV2 = "parakeet-tdt-0.6b-v2"
    case whisperSmall = "openai_whisper-small_216MB"

    public var id: String { rawValue }

    /// Best first.
    public static var ranked: [SpeechModel] { allCases }

    public var displayName: String {
        switch self {
        case .parakeetV2: "NVIDIA Parakeet TDT 0.6B v2"
        case .whisperSmall: "Whisper Small"
        }
    }

    public var accuracyNote: String {
        switch self {
        case .parakeetV2: "Most accurate for English (6.1% average word error rate on the Open ASR Leaderboard)."
        case .whisperSmall: "Less accurate than Parakeet; smaller download."
        }
    }

    public var speedNote: String {
        switch self {
        case .parakeetV2: "Fast: runs on the Neural Engine. Uses more memory while loading."
        case .whisperSmall: "Slower on long dictations; light on memory."
        }
    }

    public var isEnglishOnly: Bool { self == .parakeetV2 }

    public var languageNote: String { isEnglishOnly ? "English only" : "Automatic or English" }

    public var source: String {
        switch self {
        case .parakeetV2: "NVIDIA, CC-BY-4.0"
        case .whisperSmall: "OpenAI, MIT"
        }
    }
}

/// The user's model choice, stored in UserDefaults. Unset until they pick one.
public struct ModelChoice {
    public static let key = "speechModel"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var selected: SpeechModel? {
        defaults.string(forKey: Self.key).flatMap(SpeechModel.init(rawValue:))
    }

    /// The first-launch picker is shown only while this is true.
    public var needsChoice: Bool { selected == nil }

    public func choose(_ model: SpeechModel) {
        defaults.set(model.rawValue, forKey: Self.key)
    }
}

/// What to do about the model at launch. Pure, so "never download on its own" is tested.
public enum ModelStartup: Equatable, Sendable {
    /// Nothing is chosen: show the picker and download nothing.
    case showPicker
    /// Use the model chosen earlier. Downloading it still needs the user's opt-in.
    case use(SpeechModel)

    /// `installed` lists models whose verified files are on disk. A copy that downloaded Whisper
    /// before the picker existed keeps using it without being asked.
    public static func decide(choice: SpeechModel?, installed: Set<SpeechModel>) -> ModelStartup {
        if let choice { return .use(choice) }
        if let existing = SpeechModel.ranked.first(where: installed.contains) { return .use(existing) }
        return .showPicker
    }
}

/// The transcriber the controller talks to. It forwards to the engine for the chosen model, so
/// switching models swaps the engine without rebuilding the controller.
public actor ActiveTranscriber: Transcribing {
    public struct NoModel: Error, CustomStringConvertible, LocalizedError {
        public var description: String { "No speech model is chosen yet. Open Dictator to choose one." }
        public var errorDescription: String? { description }
    }

    private var engine: (any Transcribing)?

    public init() {}

    public func use(_ engine: (any Transcribing)?) {
        self.engine = engine
    }

    public func prepare() async throws {
        guard let engine else { throw NoModel() }
        try await engine.prepare()
    }

    public func transcribe(_ samples: [Float], language: String?) async throws -> String {
        guard let engine else { throw NoModel() }
        return try await engine.transcribe(samples, language: language)
    }
}
