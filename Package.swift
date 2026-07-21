// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PullDown",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "PullDown", targets: ["PullDown"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4"),
    ],
    targets: [
        .executableTarget(
            name: "PullDown",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/PullDown",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "PullDownTests",
            dependencies: ["PullDown"],
            path: "Tests/PullDownTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
