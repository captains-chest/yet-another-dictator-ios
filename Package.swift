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
        // The app alone links this. The only target that imports WhisperKit.
        .library(name: "WhisperTranscription", targets: ["WhisperTranscription"])
    ],
    // Every dependency is pinned exactly; Dependabot proposes bumps as PRs.
    dependencies: [
        .package(url: "https://github.com/captains-chest/DictationCore.git", exact: "0.1.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1")
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
        .testTarget(
            name: "WhisperTranscriptionTests",
            dependencies: ["WhisperTranscription", .product(name: "DictationCore", package: "DictationCore")]
        )
    ]
)
