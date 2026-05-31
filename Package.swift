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
            url: "https://github.com/iasnezhkov/sudachi-swift/releases/download/v0.2.0/SujiSudachi.xcframework.zip",
            checksum: "d1e1de22c04f878125c0a5808e172fb73690c60232a97b9e355f03e46a316388"
        ),
        .target(
            name: "SujiSudachi",
            dependencies: ["suji_sudachiFFI"],
            path: "swift/SujiSudachi/Sources/SujiSudachi"
        ),
        .testTarget(
            name: "SujiSudachiTests",
            dependencies: ["SujiSudachi"],
            path: "swift/SujiSudachi/Tests/SujiSudachiTests"
        ),
    ]
)
