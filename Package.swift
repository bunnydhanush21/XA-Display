// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "XADisplayProtocol",
    platforms: [
        .macOS(.v11),
        .iOS(.v12),
    ],
    products: [
        .library(name: "XADisplayProtocol", targets: ["XADisplayProtocol"]),
    ],
    targets: [
        .target(name: "XADisplayProtocol"),
        .testTarget(
            name: "XADisplayProtocolTests",
            dependencies: ["XADisplayProtocol"]
        ),
    ]
)
