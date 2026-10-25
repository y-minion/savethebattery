import Foundation
import CryptoKit
public struct BatterySnapshot: Codable, Sendable {
    public var timestamp: Date = Date()
    public var percent: Int?
    public var health: Int?
    public var cycles: Int?
    public var temperature: Double?
    public var watts: Double?
    public var onAC = false
    public var charging = false
    public var temperatureSource: String?
    public var healthPrecise: Double?
    public var designCapacity: Int?
    public var designCycles: Int?
    /// Kept out of JSON so pasted `vbctl status --json` output and history files carry no device identifier.
    public var batteryID: String?
    /// Raw RemainingCapacity / FullChargeCapacity, the percentage the battery hardware itself reports (macOS's `percent` is smoothed).
    public var hardwarePercent: Int?
    /// Live adapter and system power from the IORegistry; kept out of JSON like `batteryID`.
    public var power: PowerReading?
    enum CodingKeys: String, CodingKey { case timestamp, percent, health, cycles, temperature, watts, onAC, charging, temperatureSource, healthPrecise, designCapacity, designCycles, hardwarePercent }
    public init() {}
    public static func decode(_ values: [String: Any], now: Date = Date()) -> BatterySnapshot { 
        var result = BatterySnapshot(); result.timestamp = now
        let data = values["BatteryData"] as? [String: Any] ?? [:]
        func number(_ key: String) -> Double? { (values[key] as? NSNumber)?.doubleValue }
        if let p = number("CurrentCapacity"), (0...100).contains(p) { result.percent = Int(p) }
        result.cycles = (values["CycleCount"] as? NSNumber)?.intValue
        let design = (values["DesignCapacity"] as? NSNumber)?.doubleValue ?? (data["DesignCapacity"] as? NSNumber)?.doubleValue
        let full = (values["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue ?? (data["NominalChargeCapacity"] as? NSNumber)?.doubleValue ?? (data["FullChargeCapacity"] as? NSNumber)?.doubleValue
        if let design, let full, design > 0, full > 0 {
            let precise = full / design * 100
            if precise.isFinite, precise < 1e9 { result.health = min(100, Int(precise)) }
            if precise < 150 { result.healthPrecise = (precise * 10).rounded() / 10 }
        }
        if let design, design > 0, design < 1e9 { result.designCapacity = Int(design) }
        result.designCycles = (values["DesignCycleCount9C"] as? NSNumber)?.intValue
        if let serial = values["Serial"] as? String, !serial.isEmpty { result.batteryID = BatteryIdentity.hash(serial) }
        if let raw = number("Temperature"), raw > 0, raw / 100 < 100 { result.temperature = raw / 100; result.temperatureSource = "IORegistry 배터리 센서" }
        if let voltage = number("Voltage"), let current = (values["InstantAmperage"] ?? values["Amperage"]) as? NSNumber {
            let signed = Int64(bitPattern: current.uint64Value)
            if abs(Double(signed)) < 100000, voltage > 0, voltage < 100000 { result.watts = voltage * Double(signed) / 1_000_000 }
        }
        if let remaining = (data["RemainingCapacity"] as? NSNumber)?.doubleValue, let fullCharge = (data["FullChargeCapacity"] as? NSNumber)?.doubleValue, fullCharge > 0 {
            let hardware = (remaining / fullCharge * 100).rounded()
            if hardware.isFinite, (0...100).contains(hardware) { result.hardwarePercent = Int(hardware) }
        }
        result.power = PowerReading.decode(values)
        result.onAC = values["ExternalConnected"] as? Bool ?? false
        result.charging = values["IsCharging"] as? Bool ?? false
        return result
    }
}
/// Stable local identifier for battery replacement detection; the serial itself is never stored.
enum BatteryIdentity {
    static func hash(_ serial: String) -> String { SHA256.hash(data: Data(serial.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined() }
}
