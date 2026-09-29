// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DisplayToggle",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DisplayCore"),
        .executableTarget(name: "DisplayToggle", dependencies: ["DisplayCore"]),
        .testTarget(name: "DisplayCoreTests", dependencies: ["DisplayCore"]),
    ]
)
