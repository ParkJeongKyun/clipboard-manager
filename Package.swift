// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "clipboard-manager",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "clipboard-manager",
            targets: ["ClipboardManager"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "ClipboardManager",
            dependencies: ["HotKey"],
            path: "Sources",
            exclude: [
                "Resources/Info.plist"
            ],
            resources: [
                .copy("Resources/Assets.xcassets")
            ],
            swiftSettings: [
                .unsafeFlags(["-suppress-warnings"], .when(configuration: .debug))
            ]
        )
    ]
)
