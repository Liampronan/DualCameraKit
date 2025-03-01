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
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "DualCameraKit",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ]
        ),
        .testTarget(
            name: "DualCameraKitTests",
            dependencies: ["DualCameraKit"]
        ),
    ]
)
