// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "VibeBattery", platforms: [.macOS("15.0")], products: [.library(name: "BatteryCore", targets: ["BatteryCore"])], targets: [.target(name: "BatteryCore"), .testTarget(name: "BatteryCoreTests", dependencies: ["BatteryCore"])], swiftLanguageVersions: [.v5])
