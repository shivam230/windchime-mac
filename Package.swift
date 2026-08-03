// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Windchime",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Windchime", path: "Sources/Windchime")
    ]
)
