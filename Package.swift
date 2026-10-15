// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "SquirrelMacOS",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "RimeKit", targets: ["RimeKit"]),
        .executable(name: "rimectl", targets: ["rimectl"]),
        .executable(name: "SquirrelMacOSApp", targets: ["SquirrelMacOSApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    ],
    targets: [
        .target(
            name: "RimeKit",
            dependencies: [.product(name: "Yams", package: "Yams")],
            resources: [.copy("Resources/catalog.json")]
        ),
        .executableTarget(name: "rimectl", dependencies: ["RimeKit"]),
        // 应用：AppCore 是界面用的逻辑（可测，不含 SwiftUI），AppUI 是视图，SquirrelMacOSApp 只有 @main
        .target(name: "AppCore", dependencies: ["RimeKit"]),
        .target(name: "AppUI", dependencies: ["AppCore"]),
        .executableTarget(name: "SquirrelMacOSApp", dependencies: ["AppUI"]),
        .testTarget(name: "RimeKitTests", dependencies: ["RimeKit", "rimectl", "AppCore"]),
    ]
)
