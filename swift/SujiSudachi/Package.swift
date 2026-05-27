// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SujiSudachi",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SujiSudachi", targets: ["SujiSudachi"]),
    ],
    targets: [
        .binaryTarget(
            name: "suji_sudachiFFI",
            path: "../../build/SujiSudachi.xcframework"
        ),
        .target(
            name: "SujiSudachi",
            dependencies: ["suji_sudachiFFI"],
            path: "Sources/SujiSudachi"
        ),
        .testTarget(
            name: "SujiSudachiTests",
            dependencies: ["SujiSudachi"],
            path: "Tests/SujiSudachiTests"
        ),
    ]
)
