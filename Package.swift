// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "OpenShuttler",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure domain logic (models, validation, parsing, planning). No AppKit, fully testable.
        .target(
            name: "ShutterCore",
            path: "Sources/ShutterCore"
        ),
        // Menu bar application: AppKit integration over Core.
        .executableTarget(
            name: "OpenShuttler",
            dependencies: ["ShutterCore"],
            path: "Sources/OpenShuttler"
        ),
        .testTarget(
            name: "ShutterCoreTests",
            dependencies: ["ShutterCore"],
            path: "Tests/ShutterCoreTests"
        )
    ]
)
