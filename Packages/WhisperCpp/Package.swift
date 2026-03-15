// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperCpp",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WhisperCpp", targets: ["WhisperCpp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ggerganov/whisper.cpp.git", from: "1.7.2"),
    ],
    targets: [
        .target(
            name: "WhisperCpp",
            dependencies: [
                .product(name: "whisper", package: "whisper.cpp"),
            ],
            path: "Sources/WhisperCpp",
            publicHeadersPath: "include"
        ),
    ]
)
