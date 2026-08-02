// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacErnet",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacErnet", targets: ["MacErnet"])
    ],
    targets: [
        .executableTarget(
            name: "MacErnet",
            path: "Sources/MacErnet"
        ),
        .testTarget(
            name: "MacErnetTests",
            dependencies: ["MacErnet"],
            path: "Tests/MacErnetTests"
        )
    ]
)
