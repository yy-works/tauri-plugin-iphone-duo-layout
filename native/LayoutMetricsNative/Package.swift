// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LayoutMetricsNative",
    platforms: [.iOS(.v17)],
    products: [.library(name: "LayoutMetricsNative", targets: ["LayoutMetricsNative"])],
    targets: [.target(name: "LayoutMetricsNative")]
)
