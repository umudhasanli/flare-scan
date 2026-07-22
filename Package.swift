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
            path: "Sources/FlareScan",
            resources: [.process("Resources")],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "FlareScanTests",
            dependencies: ["FlareScan"],
            path: "Tests/FlareScanTests"
        )
    ]
)
