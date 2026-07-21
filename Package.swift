// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PullDown",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "PullDown", targets: ["PullDown"]),
    ],
    targets: [
        .executableTarget(
            name: "PullDown",
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
