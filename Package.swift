// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "vision-ocr",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "vision-ocr", targets: ["vision-ocr"]),
        .library(name: "VisionOCRKit", targets: ["VisionOCRKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(name: "VisionOCRKit"),
        .executableTarget(
            name: "vision-ocr",
            dependencies: [
                "VisionOCRKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "VisionOCRKitTests", dependencies: ["VisionOCRKit"]),
    ]
)
