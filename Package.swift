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
            url: "https://github.com/iasnezhkov/sudachi-swift/releases/download/v0.1.0/SujiSudachi.xcframework.zip",
            checksum: "e318ecc435b5941d149020cba64b6cb327e1307371c330517ceb96334eade96b"
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
