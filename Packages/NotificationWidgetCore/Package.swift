// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotificationWidgetCore",
    platforms: [
        // The app targets only the current macOS version the user runs (PRD §6).
        .macOS("26.0")
    ],
    products: [
        .library(name: "NotificationWidgetCore", targets: ["NotificationWidgetCore"])
    ],
    targets: [
        .target(name: "NotificationWidgetCore"),
        .testTarget(
            name: "NotificationWidgetCoreTests",
            dependencies: ["NotificationWidgetCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
