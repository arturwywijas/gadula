// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "voice-agent",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoiceAgentCore", targets: ["VoiceAgentCore"]),
        .executable(name: "Gadula", targets: ["VoiceAgentApp"]),
        .executable(name: "GadulaIconGenerator", targets: ["GadulaIconGenerator"]),
        .executable(name: "AudioTapGuardTests", targets: ["AudioTapGuardTests"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "VoiceAgentCore"),
        .target(name: "AudioTapGuard"),
        .target(name: "GadulaArtwork"),
        .executableTarget(
            name: "VoiceAgentApp",
            dependencies: [
                "VoiceAgentCore",
                "AudioTapGuard",
                "GadulaArtwork",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            resources: [
                .process("THIRD-PARTY-NOTICES.md"),
            ]
        ),
        .executableTarget(
            name: "GadulaIconGenerator",
            dependencies: ["GadulaArtwork"]
        ),
        // CLT only: no XCTest / Swift Testing. Executable harness, `swift run VoiceAgentCoreTests`.
        .executableTarget(
            name: "VoiceAgentCoreTests",
            dependencies: ["VoiceAgentCore"],
            path: "Tests/VoiceAgentCoreTests"
        ),
        .executableTarget(
            name: "AudioTapGuardTests",
            dependencies: ["AudioTapGuard"],
            path: "Tests/AudioTapGuardTests"
        ),
    ]
)
