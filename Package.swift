// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-typewriter-console",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TypewriterConsole", targets: ["TypewriterConsole"]),
    ],
    targets: [
        .target(name: "TypewriterConsole"),
        .testTarget(name: "TypewriterConsoleTests", dependencies: ["TypewriterConsole"]),
    ]
)
