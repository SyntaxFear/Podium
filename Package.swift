// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PodiumKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PodiumKit", targets: ["PodiumKit"]),
        .executable(name: "podium-smoke", targets: ["PodiumSmoke"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "PodiumKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(name: "PodiumSmoke", dependencies: ["PodiumKit"]),
        .testTarget(name: "PodiumKitTests", dependencies: ["PodiumKit"]),
    ]
)
