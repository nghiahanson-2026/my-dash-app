// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DashProtocol",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "DashProtocol", targets: ["DashProtocol"])],
    targets: [
        .target(name: "DashProtocol"),
        .testTarget(
            name: "DashProtocolTests",
            dependencies: ["DashProtocol"],
            resources: [.copy("Vectors")]
        ),
    ]
)
