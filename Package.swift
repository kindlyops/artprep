// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ArtPrep",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ArtPrep", targets: ["ArtPrep"])],
    dependencies: [.package(path: "Vendor/Sparkle")],
    targets: [
        .target(name: "ArtPrepCore"),
        .executableTarget(
            name: "ArtPrep",
            dependencies: ["ArtPrepCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(name: "ArtPrepCoreTests", dependencies: ["ArtPrepCore"]),
        .testTarget(name: "ArtPrepAppTests", dependencies: ["ArtPrep", "ArtPrepCore"]),
    ]
)
