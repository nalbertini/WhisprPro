// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperCpp",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WhisperCpp", targets: ["WhisperCpp"]),
    ],
    targets: [
        .target(
            name: "WhisperCpp",
            dependencies: ["libwhisper"],
            path: "Sources/WhisperCpp",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Foundation"),
                .linkedLibrary("c++"),
            ]
        ),
        .binaryTarget(
            name: "libwhisper",
            path: "libwhisper.xcframework"
        ),
    ]
)
