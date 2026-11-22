// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingRecord",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MeetingRecord", targets: ["MeetingRecord"])],
    targets: [
        .executableTarget(name: "MeetingRecord", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "MeetingRecordTests", dependencies: ["MeetingRecord"])
    ],
    swiftLanguageModes: [.v6]
)
