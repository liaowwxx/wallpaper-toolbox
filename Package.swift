// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RePKG-Native",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "RePKG-Native", targets: ["RePKG-Native"])
    ],
    targets: [
        .executableTarget(
            name: "RePKG-Native",
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
