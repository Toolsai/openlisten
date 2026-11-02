// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenListenCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "OpenListenCore", targets: ["OpenListenCore"])],
    targets: [
        .target(name: "OpenListenCore"),
        .testTarget(name: "OpenListenCoreTests", dependencies: ["OpenListenCore"])
    ]
)
