// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YoloLedgerUI",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "YoloLedgerUI", targets: ["YoloLedgerUI"]),
    ],
    dependencies: [
        .package(path: "../core-swift"),
    ],
    targets: [
        .target(
            name: "YoloLedgerUI",
            dependencies: [.product(name: "YoloLedgerCore", package: "core-swift")]
        ),
        .testTarget(
            name: "YoloLedgerUITests",
            dependencies: ["YoloLedgerUI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
