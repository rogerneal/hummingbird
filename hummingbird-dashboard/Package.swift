// swift-tools-version:6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "hummingbird-dashboard",
    // Apple platform minimums; Linux is also supported (SwiftPM builds on Linux by default).
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [
        .library(name: "HummingbirdDashboard", targets: ["HummingbirdDashboard"]),
        .library(name: "HummingbirdDashboardWS", targets: ["HummingbirdDashboardWS"]),
        .executable(name: "DashboardExample", targets: ["DashboardExample"]),
    ],
    dependencies: [
        // local hummingbird fork; replace with
        // .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.24.0")
        // when this package is extracted to its own repository
        .package(path: ".."),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.2.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
    ],
    targets: [
        .target(
            name: "HummingbirdDashboard",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
            ]
        ),
        .target(
            name: "HummingbirdDashboardWS",
            dependencies: [
                .byName(name: "HummingbirdDashboard"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
            ]
        ),
        .executableTarget(
            name: "DashboardExample",
            dependencies: [
                .byName(name: "HummingbirdDashboard"),
                .byName(name: "HummingbirdDashboardWS"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOEmbedded", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "HummingbirdDashboardTests",
            dependencies: [
                .byName(name: "HummingbirdDashboard"),
                .byName(name: "HummingbirdDashboardWS"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
                .product(name: "HummingbirdWSTesting", package: "hummingbird-websocket"),
            ]
        ),
    ]
)
