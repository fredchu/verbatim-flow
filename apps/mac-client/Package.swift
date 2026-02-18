// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VerbatimFlow",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "verbatim-flow", targets: ["VerbatimFlow"])
    ],
    targets: [
        .executableTarget(
            name: "VerbatimFlow",
            path: "Sources/VerbatimFlow"
        ),
        .testTarget(
            name: "VerbatimFlowTests",
            dependencies: ["VerbatimFlow"],
            path: "Tests/VerbatimFlowTests"
        )
    ]
)
