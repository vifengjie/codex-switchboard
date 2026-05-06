// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "CodexSwitchboard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CodexQuotaManager",
            targets: ["CodexQuotaManagerApp"]
        ),
        .library(
            name: "CodexQuotaCore",
            targets: ["CodexQuotaCore"]
        ),
        .library(
            name: "CodexQuotaCollectors",
            targets: ["CodexQuotaCollectors"]
        ),
        .library(
            name: "CodexQuotaStorage",
            targets: ["CodexQuotaStorage"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CodexQuotaManagerApp",
            dependencies: [
                "CodexQuotaCore",
                "CodexQuotaCollectors",
                "CodexQuotaStorage"
            ],
            path: "App"
        ),
        .target(
            name: "CodexQuotaCore",
            path: "Sources/Core"
        ),
        .target(
            name: "CodexQuotaCollectors",
            dependencies: [
                "CodexQuotaCore",
                "CodexQuotaStorage"
            ],
            path: "Sources/Collectors"
        ),
        .target(
            name: "CodexQuotaStorage",
            dependencies: ["CodexQuotaCore"],
            path: "Sources/Storage",
            exclude: ["Migrations/README.md"]
        ),
        .testTarget(
            name: "CodexQuotaCoreTests",
            dependencies: ["CodexQuotaCore"],
            path: "Tests/CoreTests"
        ),
        .testTarget(
            name: "CodexQuotaCollectorTests",
            dependencies: [
                "CodexQuotaCollectors",
                "CodexQuotaStorage"
            ],
            path: "Tests/CollectorTests",
            resources: [
                .process("../../Fixtures/codex-jsonl")
            ]
        ),
        .testTarget(
            name: "CodexQuotaStorageTests",
            dependencies: ["CodexQuotaStorage"],
            path: "Tests/StorageTests"
        )
    ]
)
