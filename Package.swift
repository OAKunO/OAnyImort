// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OAnyImport",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OAnyImport", targets: ["OAnyImportApp"])],
    targets: [
        .target(name: "OAnyImportCore"),
        .executableTarget(name: "OAnyImportApp", dependencies: ["OAnyImportCore"]),
        .testTarget(name: "OAnyImportCoreTests", dependencies: ["OAnyImportCore"])
    ]
)
