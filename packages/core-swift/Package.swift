// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YoloLedgerCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "YoloLedgerCore", targets: ["YoloLedgerCore"]),
    ],
    targets: [
        .target(name: "YoloLedgerCore"),
        .testTarget(name: "YoloLedgerCoreTests", dependencies: ["YoloLedgerCore"]),
    ],
    swiftLanguageModes: [.v6]
)
