// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "clipboard-manager",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "clipboard-manager",
            targets: ["ClipboardManager"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ClipboardManager",
            dependencies: [],
            path: "Sources",
            swiftSettings: [
                .unsafeFlags(["-suppress-warnings"], .when(configuration: .debug))
            ]
        )
    ]
)
