// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RoundPlayEngine",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
    products: [
        .library(name: "RoundPlayEngine", targets: ["RoundPlayEngine"])
    ],
    targets: [
        .target(name: "RoundPlayEngine"),
        .testTarget(
            name: "RoundPlayEngineTests",
            dependencies: ["RoundPlayEngine"],
            resources: [.copy("Fixtures")]
        )
    ]
)
