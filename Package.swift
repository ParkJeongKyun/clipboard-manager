// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "clipboard-manager",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "ClipboardManager", targets: ["ClipboardManager"])
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "ClipboardManager",
            dependencies: ["HotKey"]
        ),
        .testTarget(
            name: "ClipboardManagerTests",
            dependencies: ["ClipboardManager"]
        )
    ],
    swiftLanguageModes: [.v5]
)
