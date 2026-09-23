// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Mundane",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Mundane", path: "Sources/Mundane"),
        .testTarget(name: "MundaneTests", dependencies: ["Mundane"],
                    path: "Tests/MundaneTests")
    ]
)
