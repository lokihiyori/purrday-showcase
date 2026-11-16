// swift-tools-version: 6.2
// Purrday 的纯 Swift 核心逻辑。
// 约束：CatEngine、Economy、CatWorld 不得 import SwiftUI / UIKit / SwiftData，
// 必须能在 Linux 上 `swift build && swift test`。

import PackageDescription

let package = Package(
    name: "PurrdayCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "CatEngine", targets: ["CatEngine"]),
        .library(name: "Economy", targets: ["Economy"]),
        .library(name: "CatWorld", targets: ["CatWorld"]),
    ],
    targets: [
        .target(name: "CatEngine"),
        .target(
            name: "Economy",
            dependencies: ["CatEngine"],
            resources: [.process("Resources")]
        ),
        .target(name: "CatWorld", dependencies: ["CatEngine", "Economy"]),
        .testTarget(name: "CatEngineTests", dependencies: ["CatEngine"]),
        .testTarget(name: "EconomyTests", dependencies: ["Economy", "CatEngine"]),
        .testTarget(name: "CatWorldTests", dependencies: ["CatWorld", "Economy", "CatEngine"]),
    ],
    swiftLanguageModes: [.v6]
)
