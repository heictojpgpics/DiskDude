// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DiskDudeCross",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DiskDudeCore", targets: ["DiskDudeCore"]),
        .executable(name: "diskdude-cli", targets: ["DiskDudeCLI"]),
    ],
    targets: [
        .target(name: "DiskDudeCore"),
        .executableTarget(name: "DiskDudeCLI", dependencies: ["DiskDudeCore"]),
        .testTarget(name: "DiskDudeCoreTests", dependencies: ["DiskDudeCore"]),
    ]
)
