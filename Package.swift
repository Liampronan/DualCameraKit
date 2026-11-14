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
        ),
        .library(
            name: "DualCameraEmojiKit",
            targets: ["DualCameraEmojiKit"]
        ),
        .library(
            name: "DualCameraEmojiKitUI",
            targets: ["DualCameraEmojiKitUI"]
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
        .target(
            name: "DualCameraEmojiKit",
            dependencies: ["DualCameraKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "DualCameraEmojiKitUI",
            dependencies: ["DualCameraKit", "DualCameraKitUI", "DualCameraEmojiKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "DualCameraKitTests",
            dependencies: [
                "DualCameraKit",
                "DualCameraKitUI",
                "DualCameraEmojiKit",
                "DualCameraEmojiKitUI"
            ],
            path: "Tests"
        )
    ]
)
