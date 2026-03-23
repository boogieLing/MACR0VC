// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftRVCMacClient",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "SwiftRVCMacClient",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "SwiftRVCMacClientTests",
            dependencies: ["SwiftRVCMacClient"]
        ),
    ]
)
