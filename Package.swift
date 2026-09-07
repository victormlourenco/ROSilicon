// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ROSilicon",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ROSilicon",
            path: "Sources/ROSilicon"
        )
    ]
)
