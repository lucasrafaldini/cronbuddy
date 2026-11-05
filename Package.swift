// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CronBuddy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CronBuddy", targets: ["CronBuddy"]),
    ],
    targets: [
        .target(name: "CronBuddyCore"),
        .executableTarget(name: "CronBuddy", dependencies: ["CronBuddyCore"]),
        .testTarget(name: "CronBuddyCoreTests", dependencies: ["CronBuddyCore"]),
    ]
)
