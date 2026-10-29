// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "scoop",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/tomasf/Cadova.git", from: "1.2.0"),
        .package(url: "https://github.com/tomasf/Apus.git", .upToNextMinor(from: "0.2.1")),
    ],
    targets: [
        .executableTarget(
            name: "scoop",
            dependencies: ["Cadova", "Apus"],
            resources: [.copy("Resources/Fredoka.ttf"), .copy("Resources/Fredoka-OFL.txt")],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        .testTarget(
            name: "ScoopTests",
            dependencies: ["scoop", "Cadova"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
    ]
)
