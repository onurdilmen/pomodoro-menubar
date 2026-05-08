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
            ]
            // index.html is copied into Pomodoro.app/Contents/Resources/ by package.sh.
            // We deliberately don't use SwiftPM's resources: pipeline because
            // Bundle.module's auto-generated accessor hardcodes the build-time
            // path, which breaks once the .app is shipped to other machines.
        )
    ]
)
