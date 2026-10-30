// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SaveTheBattery", platforms: [.macOS("15.0")], products: [
    .executable(name: "SaveTheBattery", targets: ["SaveTheBattery"]),
    .executable(name: "stb", targets: ["BatteryCLI"]),
    .executable(name: "STBChargeHelper", targets: ["STBChargeHelper"]),
    .library(name: "BatteryCore", targets: ["BatteryCore"]),
    .library(name: "BatteryPlatform", targets: ["BatteryPlatform"]),
    .library(name: "MacBridge", targets: ["MacBridge"])
], targets: [
    .target(name: "BatteryCore"),
    .target(name: "MacBridge", linkerSettings: [.linkedLibrary("proc"), .linkedFramework("Foundation"), .linkedFramework("IOKit")]),
    .target(name: "BatteryPlatform", dependencies: ["BatteryCore", "MacBridge"], linkerSettings: [.linkedFramework("IOKit")]),
    .executableTarget(name: "SaveTheBattery", dependencies: ["BatteryCore", "BatteryPlatform"]),
    .executableTarget(name: "BatteryCLI", dependencies: ["BatteryCore", "BatteryPlatform", "MacBridge"]),
    .executableTarget(name: "STBChargeHelper", dependencies: ["BatteryCore", "BatteryPlatform", "MacBridge"], linkerSettings: [.linkedFramework("SystemConfiguration")]),
    .testTarget(name: "BatteryCoreTests", dependencies: ["BatteryCore", "BatteryPlatform", "MacBridge"])
], swiftLanguageVersions: [.v5])
