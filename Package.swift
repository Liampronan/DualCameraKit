// swift-tools-version: 6.0
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
        )
    ],
    targets: [
        .target(
            name: "DualCameraKit",
            resources: [
                .process("DualCameraShaders.metal")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "DualCameraKitUI",
            dependencies: ["DualCameraKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "DualCameraKitTests",
            dependencies: ["DualCameraKit", "DualCameraKitUI"],
            path: "Tests"
        )
    ]
)
