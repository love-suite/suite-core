// swift-tools-version:5.9
import PackageDescription

// What every app of the suite shares: where Explorer's settings live (`SuiteDefaults`), the messages between
// the apps (`ExplorerLink`, `ClipboardMessage`, `BindingsMessage`), what one app knows of another
// (`SuiteApps`), settings profiles, updates. What only the apps handling files need is in suite-files.
let package = Package(
    name: "SuiteCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SuiteCore", targets: ["SuiteCore"]),
    ],
    targets: [
        .target(name: "SuiteCore", resources: [.process("Resources")]),
        .testTarget(name: "SuiteCoreTests", dependencies: ["SuiteCore"]),
    ]
)
