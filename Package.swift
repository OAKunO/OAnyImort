// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OAnyImort",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OAnyImort", targets: ["OAnyImortApp"])],
    targets: [
        .target(name: "OAnyImortCore"),
        .executableTarget(name: "OAnyImortApp", dependencies: ["OAnyImortCore"]),
        .testTarget(name: "OAnyImortCoreTests", dependencies: ["OAnyImortCore"])
    ]
)
