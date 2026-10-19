import Foundation
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
    public init() {}
    public static func decode(_ values: [String: Any], now: Date = Date()) -> BatterySnapshot { 
        var result = BatterySnapshot(); result.timestamp = now
        let data = values["BatteryData"] as? [String: Any] ?? [:]
        func number(_ key: String) -> Double? { (values[key] as? NSNumber)?.doubleValue }
        if let p = number("CurrentCapacity"), (0...100).contains(p) { result.percent = Int(p) }
        result.cycles = (values["CycleCount"] as? NSNumber)?.intValue
        let design = (values["DesignCapacity"] as? NSNumber)?.doubleValue ?? (data["DesignCapacity"] as? NSNumber)?.doubleValue
        let full = (values["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue ?? (data["NominalChargeCapacity"] as? NSNumber)?.doubleValue ?? (data["FullChargeCapacity"] as? NSNumber)?.doubleValue
        if let design, let full, design > 0, full > 0 { result.health = min(100, Int(full / design * 100)) }
        if let raw = number("Temperature"), raw > 0, raw / 100 < 100 { result.temperature = raw / 100; result.temperatureSource = "IORegistry 배터리 센서" }
        if let voltage = number("Voltage"), let current = (values["InstantAmperage"] ?? values["Amperage"]) as? NSNumber {
            let signed = Int64(bitPattern: current.uint64Value)
            if abs(Double(signed)) < 100000, voltage > 0, voltage < 100000 { result.watts = voltage * Double(signed) / 1_000_000 }
        }
        result.onAC = values["ExternalConnected"] as? Bool ?? false
        result.charging = values["IsCharging"] as? Bool ?? false
        return result
    }
}
