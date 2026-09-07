// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ROLatamLauncher",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ROLatamLauncher",
            path: "Sources/ROLatamLauncher"
        )
    ]
)
