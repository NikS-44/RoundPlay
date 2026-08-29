// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RoundPlayData",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "RoundPlayData", targets: ["RoundPlayData"])
    ],
    dependencies: [
        .package(path: "../RoundPlayEngine")
    ],
    targets: [
        .target(
            name: "RoundPlayData",
            dependencies: ["RoundPlayEngine"]
        ),
        .testTarget(
            name: "RoundPlayDataTests",
            dependencies: ["RoundPlayData"]
        )
    ]
)
