// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "tauri-plugin-iphone-duo-layout",
    platforms: [.iOS(.v17)],
    products: [.library(name: "tauri-plugin-iphone-duo-layout", type: .static, targets: ["tauri-plugin-iphone-duo-layout"])],
    dependencies: [
        .package(name: "Tauri", path: "../.tauri/tauri-api"),
        .package(path: "../native/LayoutMetricsNative")
    ],
    targets: [.target(name: "tauri-plugin-iphone-duo-layout", dependencies: [
        .byName(name: "Tauri"), .product(name: "LayoutMetricsNative", package: "LayoutMetricsNative")
    ], path: "Sources")]
)
