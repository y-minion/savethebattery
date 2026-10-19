// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "VibeBattery", platforms: [.macOS("15.0")], products: [
    .library(name: "BatteryCore", targets: ["BatteryCore"]),
    .library(name: "BatteryPlatform", targets: ["BatteryPlatform"])
], targets: [
    .target(name: "BatteryCore"),
    .target(name: "MacBridge", linkerSettings: [.linkedLibrary("proc")]),
    .target(name: "BatteryPlatform", dependencies: ["BatteryCore", "MacBridge"], linkerSettings: [.linkedFramework("IOKit")]),
    .testTarget(name: "BatteryCoreTests", dependencies: ["BatteryCore", "BatteryPlatform"])
], swiftLanguageVersions: [.v5])
