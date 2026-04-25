// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Glint",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
    ],
    targets: [
        .executableTarget(
            name: "Glint",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ],
            path: "Glint",
            exclude: ["Glint.entitlements"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "GlintTests",
            dependencies: ["Glint"],
            path: "GlintTests"
        ),
    ]
)
