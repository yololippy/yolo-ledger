// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YoloLedgerStorage",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "YoloLedgerStorage", targets: ["YoloLedgerStorage"]),
    ],
    dependencies: [
        .package(path: "../core-swift"),
    ],
    targets: [
        .target(
            name: "YoloLedgerStorage",
            dependencies: [
                .product(name: "YoloLedgerCore", package: "core-swift"),
            ]
        ),
        .testTarget(
            name: "YoloLedgerStorageTests",
            dependencies: [
                "YoloLedgerStorage",
                .product(name: "YoloLedgerCore", package: "core-swift"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
