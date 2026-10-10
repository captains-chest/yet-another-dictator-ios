// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DictatorIOS",
    // iOS 18: DictationCore needs it (Synchronization.Mutex).
    platforms: [.iOS(.v18)],
    // Every dependency is pinned exactly; Dependabot proposes bumps as PRs.
    dependencies: [
        .package(url: "https://github.com/captains-chest/DictationCore.git", exact: "0.1.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1")
    ],
    targets: [
        .target(
            name: "DictatorIOS",
            dependencies: [
                .product(name: "DictationCore", package: "DictationCore"),
                .product(name: "WhisperKit", package: "WhisperKit")
            ]
        )
    ]
)
