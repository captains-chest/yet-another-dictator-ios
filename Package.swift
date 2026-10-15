// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DictatorIOS",
    // iOS 18: DictationCore needs it (Synchronization.Mutex).
    // macOS only so the platform-free targets can be unit-tested on a Mac host; the app is iOS-only.
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        // Shared by the app and the keyboard extension. Does not link WhisperKit: the extension's
        // memory budget can't hold the model (ADR 0001).
        .library(name: "DictatorIOS", targets: ["DictatorIOS"]),
        // The app alone links this: the speech engines and the model choice. WhisperTranscription is
        // the only target that imports WhisperKit, ParakeetTranscription the only one that imports
        // FluidAudio. One product, so the Xcode project's package dependency stays the same.
        .library(name: "WhisperTranscription", targets: ["WhisperTranscription", "ParakeetTranscription", "SpeechModels"])
    ],
    // Every dependency is pinned exactly; Dependabot proposes bumps as PRs.
    dependencies: [
        .package(url: "https://github.com/captains-chest/DictationCore.git", branch: "english-only"), // TODO: exact "0.3.0" after Core is tagged
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1"),
        // Parakeet TDT (Core ML). The NemoTextProcessing trait (a prebuilt text-normalisation binary
        // we don't use) is off, so only FluidAudio's own source is linked.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: [])
    ],
    targets: [
        // Typing into the host app's field through the keyboard's text document proxy. Depends only
        // on DictationCore, so it's unit-tested anywhere (including Linux) with a fake proxy.
        .target(
            name: "KeyboardInsertion",
            dependencies: [.product(name: "DictationCore", package: "DictationCore")]
        ),
        // Transcript hand-off: the keyboard writes commands, the app writes the latest transcript,
        // and the file is deleted once the keyboard has typed it (ADR 0001). No audio.
        .target(
            name: "SessionMailbox",
            dependencies: [
                "KeyboardInsertion",
                .product(name: "DictationCore", package: "DictationCore")
            ]
        ),
        .target(
            name: "WhisperTranscription",
            dependencies: [
                .product(name: "DictationCore", package: "DictationCore"),
                .product(name: "WhisperKit", package: "WhisperKit")
            ]
        ),
        // NVIDIA Parakeet TDT 0.6B v2 (English) through FluidAudio, loaded only from the verified folder.
        .target(
            name: "ParakeetTranscription",
            dependencies: [
                .product(name: "DictationCore", package: "DictationCore"),
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        ),
        // Which models exist (best first), the user's choice, and the launch decision. UI-free.
        .target(
            name: "SpeechModels",
            dependencies: [.product(name: "DictationCore", package: "DictationCore")]
        ),
        .target(
            name: "DictatorIOS",
            dependencies: [
                "KeyboardInsertion",
                "SessionMailbox",
                .product(name: "DictationCore", package: "DictationCore")
            ]
        ),
        .testTarget(name: "KeyboardInsertionTests", dependencies: ["KeyboardInsertion"]),
        .testTarget(
            name: "SessionMailboxTests",
            dependencies: ["SessionMailbox", .product(name: "DictationCore", package: "DictationCore")]
        ),
        .testTarget(name: "ParakeetTranscriptionTests", dependencies: ["ParakeetTranscription"]),
        .testTarget(
            name: "SpeechModelsTests",
            dependencies: ["SpeechModels", "WhisperTranscription", .product(name: "DictationCore", package: "DictationCore")]
        ),
        .testTarget(
            name: "WhisperTranscriptionTests",
            dependencies: ["WhisperTranscription", .product(name: "DictationCore", package: "DictationCore")]
        )
    ]
)
