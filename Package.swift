// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "SquirrelMacOS",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "RimeKit", targets: ["RimeKit"]),
        .executable(name: "rimectl", targets: ["rimectl"]),
    ],
    targets: [
        .target(
            name: "RimeKit",
            resources: [.copy("Resources/catalog.json")]
        ),
        .executableTarget(name: "rimectl", dependencies: ["RimeKit"]),
        .testTarget(name: "RimeKitTests", dependencies: ["RimeKit", "rimectl"]),
    ]
)
