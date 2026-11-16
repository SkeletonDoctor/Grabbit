// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Grabbit",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Grabbit",
            path: "Sources/Grabbit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
