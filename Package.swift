// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "iSnow",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "iSnow",
            path: "Sources/iSnow"
        ),
        .testTarget(name: "iSnowTests", dependencies: ["iSnow"], path: "Tests/iSnowTests")
    ]
)
