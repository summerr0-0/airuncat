// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clawde",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Clawde",
            path: "Sources/Clawde"
        )
    ]
)
