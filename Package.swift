// swift-tools-version: 5.9
import PackageDescription

// Capacitor 8 iOS projects are SPM-based; the podspec is kept for CocoaPods consumers.
// The only dependency is Capacitor itself - no third-party Swift packages.
let package = Package(
    name: "CapacitorTokenVault",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "CapacitorTokenVault",
            targets: ["TokenVaultPlugin"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0")
    ],
    targets: [
        .target(
            name: "TokenVaultPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm"),
            ],
            path: "ios/Sources/TokenVaultPlugin"
        ),
        .testTarget(
            name: "TokenVaultPluginTests",
            dependencies: ["TokenVaultPlugin"],
            path: "ios/Tests/TokenVaultPluginTests"
        ),
    ]
)
