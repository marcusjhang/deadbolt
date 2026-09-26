// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Deadbolt",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DeadboltCore", targets: ["DeadboltCore"]),
        .executable(name: "deadboltctl", targets: ["deadboltctl"]),
        .executable(name: "Deadbolt", targets: ["Deadbolt"]),
    ],
    targets: [
        .target(name: "DeadboltCore"),
        .executableTarget(name: "deadboltctl", dependencies: ["DeadboltCore"]),
        .executableTarget(name: "Deadbolt", dependencies: ["DeadboltCore"]),
        .testTarget(name: "DeadboltCoreTests", dependencies: ["DeadboltCore"]),
    ]
)
