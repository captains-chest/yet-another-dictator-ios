// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DictatorIOS",
    platforms: [.iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/captains-chest/DictationCore.git", branch: "main"),
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
