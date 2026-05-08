// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PomodoroMenubar",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "PomodoroMenubar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources")]
        )
    ]
)
