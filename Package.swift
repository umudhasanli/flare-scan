// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlareScan",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FlareScan", targets: ["FlareScan"])
    ],
    targets: [
        .executableTarget(
            name: "FlareScan",
            path: "Sources/DiskLens",
            resources: [.process("Resources")],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
