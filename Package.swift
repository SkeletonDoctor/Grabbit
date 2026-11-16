// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "YTDown",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "YTDown",
            path: "Sources/YTDown",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
