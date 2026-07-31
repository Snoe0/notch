// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Notch",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NotchKit", path: "Sources/NotchKit"),
        .executableTarget(name: "Notch", dependencies: ["NotchKit"], path: "Sources/Notch"),
        .testTarget(name: "NotchKitTests", dependencies: ["NotchKit"], path: "Tests/NotchKitTests"),
    ]
)
