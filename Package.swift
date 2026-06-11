// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Wordiy",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
    ],
    products: [
        .library(
            name: "Wordiy",
            targets: ["Wordiy"])
    ],
    targets: [
        .target(
            name: "Wordiy"),
        .testTarget(
            name: "WordiyTests",
            dependencies: ["Wordiy"],
            resources: [
                .copy("Resources")
            ]),
    ]
)
