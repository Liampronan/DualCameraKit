// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DualCameraKit",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "DualCameraKit",
            targets: ["DualCameraKit"]
        ),
        .library(
            name: "DualCameraKitUI",
            targets: ["DualCameraKitUI"]
        ),
    ],
    targets: [
        .target(
            name: "DualCameraKit",
            resources: [
                .process("DualCameraShaders.metal")
            ],
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        ),
        .target(
            name: "DualCameraKitUI",
            dependencies: ["DualCameraKit"],
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        ),
        .testTarget(
            name: "DualCameraKitTests",
            dependencies: ["DualCameraKit", "DualCameraKitUI"],
            path: "Tests"
        )
    ]
)
