// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JSONFormatterApp",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "JSONCore",
            path: "Sources/JSONCore"
        ),
        .executableTarget(
            name: "JSONFormatterApp",
            dependencies: ["JSONCore"],
            path: "Sources/JSONFormatterApp"
        ),
        .executableTarget(
            name: "SelfTest",
            dependencies: ["JSONCore"],
            path: "Sources/SelfTest"
        )
    ]
)
