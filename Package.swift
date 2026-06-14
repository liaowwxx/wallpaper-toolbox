// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WallPaper-Gallery",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "WallPaper-Gallery", targets: ["WallPaper-Gallery"])
    ],
    targets: [
        .executableTarget(
            name: "WallPaper-Gallery",
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
