// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HarmonyPlayer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HarmonyPlayer", targets: ["HarmonyPlayer"])
    ],
    targets: [
        .executableTarget(
            name: "HarmonyPlayer",
            path: "Sources/HarmonyPlayer",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("MediaPlayer")
            ]
        )
    ]
)
