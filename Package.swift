// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PomodoroMenubar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PomodoroMenubar",
            resources: [.process("Resources")]
        )
    ]
)
