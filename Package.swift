// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FocusDock",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "FocusDock", targets: ["FocusDockApp"])],
    targets: [
        .target(name: "FocusDockCore"),
        .executableTarget(name: "FocusDockApp", dependencies: ["FocusDockCore"]),
        .executableTarget(name: "FocusDockQAFixtures", dependencies: ["FocusDockCore"], path: "Tests/FocusDockQAFixtures"),
        .testTarget(name: "FocusDockCoreTests", dependencies: ["FocusDockCore"])
    ],
    swiftLanguageModes: [.v5]
)
