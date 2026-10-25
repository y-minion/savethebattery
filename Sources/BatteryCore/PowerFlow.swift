import Foundation
public struct PowerReading: Equatable, Sendable {
    public var adapterName: String?
    public var adapterWatts: Int?
    public var inputW: Double?
    public var systemW: Double?
    public init(adapterName: String? = nil, adapterWatts: Int? = nil, inputW: Double? = nil, systemW: Double? = nil) { self.adapterName = adapterName; self.adapterWatts = adapterWatts; self.inputW = inputW; self.systemW = systemW }
    static func decode(_ values: [String: Any]) -> PowerReading? {
        let telemetry = values["PowerTelemetryData"] as? [String: Any] ?? [:], adapter = values["AdapterDetails"] as? [String: Any] ?? [:]
        let name = (adapter["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reading = PowerReading(adapterName: name?.isEmpty == false ? name : nil, adapterWatts: (adapter["Watts"] as? NSNumber)?.intValue,
            inputW: (telemetry["SystemPowerIn"] as? NSNumber).map { $0.doubleValue / 1000 }, systemW: (telemetry["SystemLoad"] as? NSNumber).map { $0.doubleValue / 1000 })
        return reading == PowerReading() ? nil : reading
    }
}
public enum PowerSegment: Equatable, Sendable {
    case adapterToMac(Double), adapterToBattery(Double), batteryToMac(Double)
    public var label: String {
        switch self {
        case .adapterToMac(let w): return String(format: "맥 %.0f W", w)
        case .adapterToBattery(let w): return String(format: "배터리 +%.0f W", w)
        case .batteryToMac(let w): return String(format: "배터리에서 %.0f W", w)
        }
    }
}
public struct PowerSummary: Equatable, Sendable {
    public var headline: String
    public var adapter: String?
    public var segments: [PowerSegment]
    public static func make(_ b: BatterySnapshot) -> PowerSummary? {
        func w(_ v: Double) -> String { String(format: "%.0f", v) }
        if b.onAC {
            guard let input = b.power?.inputW, input > 0 else { return nil }
            let battery = b.watts ?? 0, enter = "충전기에서 \(w(input)) W 들어옴"
            if battery >= 0.5 { return PowerSummary(headline: enter, adapter: adapterText(b.power), segments: [.adapterToMac(max(0, input - battery)), .adapterToBattery(battery)]) }
            if battery > -0.5 { return PowerSummary(headline: enter, adapter: adapterText(b.power), segments: [.adapterToMac(input)]) }
            return PowerSummary(headline: "충전기 \(w(input)) W + 배터리 \(w(-battery)) W 사용", adapter: adapterText(b.power), segments: [.adapterToMac(input), .batteryToMac(-battery)])
        }
        guard let battery = b.watts else { return nil }
        return PowerSummary(headline: "배터리에서 \(w(abs(battery))) W 사용", adapter: nil, segments: [.batteryToMac(abs(battery))])
    }
    private static func adapterText(_ p: PowerReading?) -> String? {
        guard let watts = p?.adapterWatts else { return nil }
        let name = (p?.adapterName ?? "").replacingOccurrences(of: "Power Adapter", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Apple names usually already lead with the wattage ("70W USB-C Power Adapter").
        return name.isEmpty ? "\(watts)W" : name.hasPrefix("\(watts)W") ? name : "\(watts)W \(name)"
    }
}
