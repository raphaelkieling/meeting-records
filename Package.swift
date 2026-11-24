// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingRecord",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MeetingRecord", targets: ["MeetingRecord"])],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "0.15.0")
    ],
    targets: [
        .binaryTarget(name: "CTranscribe",
            url: "https://github.com/handy-computer/transcribe.cpp/releases/download/v0.4.2/TranscribeCpp.xcframework.zip",
            checksum: "650a42ee7836558d3047f328078be2b8a8d4c6e9f6a0a3f4ea145481ad1c1a86"),
        .executableTarget(name: "MeetingRecord", dependencies: [
            .product(name: "WhisperKit", package: "argmax-oss-swift"),
            "CTranscribe"
        ], linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "MeetingRecordTests", dependencies: ["MeetingRecord"])
    ],
    swiftLanguageModes: [.v6]
)
