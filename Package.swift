// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AltTabClone",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "AltTabClone",
            path: "Sources/AltTabClone"
        )
    ]
)
