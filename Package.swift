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
        .executableTarget(name: "MeetingRecord", dependencies: [
            .product(name: "WhisperKit", package: "argmax-oss-swift")
        ], linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "MeetingRecordTests", dependencies: ["MeetingRecord"])
    ],
    swiftLanguageModes: [.v6]
)
