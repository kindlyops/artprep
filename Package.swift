// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ArtPrep",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ArtPrep", targets: ["ArtPrep"])],
    targets: [
        .target(name: "ArtPrepCore"),
        .executableTarget(name: "ArtPrep", dependencies: ["ArtPrepCore"]),
        .testTarget(name: "ArtPrepCoreTests", dependencies: ["ArtPrepCore"]),
    ]
)
