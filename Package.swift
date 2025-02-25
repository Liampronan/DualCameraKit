// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DualCameraKit",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "DualCameraKit",
            targets: ["DualCameraKit"]
        ),
    ],
    targets: [
        .target(
            name: "DualCameraKit",
            dependencies: []
        ),
        .testTarget(
            name: "DualCameraKitTests",
            dependencies: ["DualCameraKit"]
        ),
    ]
)
