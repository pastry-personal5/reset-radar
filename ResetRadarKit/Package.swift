// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ResetRadarKit",
    platforms: [.iOS("26.1"), .watchOS("26.6"), .macOS("26.7.1")],
    products: [
        .library(name: "ResetRadarDomain", targets: ["ResetRadarDomain"]),
        .library(name: "ResetRadarApplication", targets: ["ResetRadarApplication"]),
        .library(name: "ResetRadarStorage", targets: ["ResetRadarStorage"]),
        .library(name: "ResetRadarTransport", targets: ["ResetRadarTransport"]),
        .library(name: "ResetRadarScheduling", targets: ["ResetRadarScheduling"]),
        .library(name: "ResetRadarWatchSync", targets: ["ResetRadarWatchSync"]),
        .library(name: "ResetRadarProviderAdapters", targets: ["ResetRadarProviderAdapters"]),
        .library(name: "ResetRadarUI", targets: ["ResetRadarUI"]),
        .library(name: "ResetRadarTestSupport", targets: ["ResetRadarTestSupport"]),
    ],
    targets: [
        .target(name: "ResetRadarDomain", dependencies: []),
        .target(name: "ResetRadarApplication", dependencies: ["ResetRadarDomain"]),
        .target(
            name: "ResetRadarStorage", dependencies: ["ResetRadarDomain", "ResetRadarApplication"]),
        .target(
            name: "ResetRadarTransport",
            dependencies: ["ResetRadarDomain", "ResetRadarApplication"]),
        .target(
            name: "ResetRadarScheduling",
            dependencies: ["ResetRadarDomain", "ResetRadarApplication"]),
        .target(
            name: "ResetRadarWatchSync",
            dependencies: ["ResetRadarDomain", "ResetRadarApplication"]),
        .target(
            name: "ResetRadarProviderAdapters",
            dependencies: ["ResetRadarDomain", "ResetRadarApplication"]),
        .target(name: "ResetRadarUI", dependencies: ["ResetRadarDomain", "ResetRadarApplication"]),
        .target(
            name: "ResetRadarTestSupport",
            dependencies: ["ResetRadarDomain", "ResetRadarApplication"]),
        .testTarget(name: "ResetRadarDomainTests", dependencies: ["ResetRadarDomain"]),
        .testTarget(
            name: "ResetRadarApplicationTests",
            dependencies: ["ResetRadarDomain", "ResetRadarApplication", "ResetRadarTestSupport"]),
        .testTarget(
            name: "ResetRadarStorageTests",
            dependencies: [
                "ResetRadarDomain", "ResetRadarApplication", "ResetRadarStorage",
                "ResetRadarTestSupport",
            ]),
        .testTarget(
            name: "ResetRadarTransportTests",
            dependencies: [
                "ResetRadarDomain", "ResetRadarApplication", "ResetRadarTransport",
                "ResetRadarTestSupport",
            ]),
        .testTarget(
            name: "ResetRadarSchedulingTests",
            dependencies: [
                "ResetRadarDomain", "ResetRadarApplication", "ResetRadarScheduling",
                "ResetRadarTestSupport",
            ]),
        .testTarget(
            name: "ResetRadarWatchSyncTests",
            dependencies: ["ResetRadarWatchSync", "ResetRadarTestSupport"]),
        .testTarget(
            name: "ResetRadarProviderAdaptersTests",
            dependencies: [
                "ResetRadarDomain", "ResetRadarApplication", "ResetRadarProviderAdapters",
                "ResetRadarTestSupport",
            ]),
        .testTarget(
            name: "ResetRadarUIComponentTests",
            dependencies: [
                "ResetRadarDomain", "ResetRadarApplication", "ResetRadarUI",
                "ResetRadarTestSupport",
            ]),
    ]
)
