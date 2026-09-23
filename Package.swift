// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AltTabClone",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // Pure, AppKit-free logic (ordering, selection, filtering) so it can be unit tested.
        .target(
            name: "AltTabCore",
            path: "Sources/AltTabCore"
        ),
        .executableTarget(
            name: "AltTabClone",
            dependencies: ["AltTabCore"],
            path: "Sources/AltTabClone"
        ),
        .testTarget(
            name: "AltTabCoreTests",
            dependencies: ["AltTabCore"],
            path: "Tests/AltTabCoreTests"
        ),
    ]
)
