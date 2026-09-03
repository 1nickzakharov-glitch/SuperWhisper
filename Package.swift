// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SuperWhisper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "SuperWhisper",
            targets: ["SuperWhisper"]
        ),
        .executable(
            name: "VerifyLongSpeech",
            targets: ["VerifyLongSpeech"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.11.0")
    ],
    targets: [
        .executableTarget(
            name: "SuperWhisper",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Sources/SuperWhisper"
        ),
        .executableTarget(
            name: "VerifyLongSpeech",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Sources/VerifyLongSpeech"
        )
    ]
)
