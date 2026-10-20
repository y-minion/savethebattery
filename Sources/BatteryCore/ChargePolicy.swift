import Foundation
public struct ChargeSettings {
    public var upper = 80; public var lower = 75
    public var heatStop = 35.0; public var heatResume = 33.0
    public var heatProtection = false
    public init() {}
}
public enum ChargeDecision: String { case charge, hold, heatHold, unknown }
public enum ChargePolicy {
    public static func decide(snapshot: BatterySnapshot, settings: ChargeSettings, previous: ChargeDecision, now: Date = Date()) -> ChargeDecision {
        guard now.timeIntervalSince(snapshot.timestamp) >= -5, now.timeIntervalSince(snapshot.timestamp) <= 90,
              snapshot.onAC, let percent = snapshot.percent,
              settings.lower >= 0, settings.upper <= 100, settings.lower < settings.upper else { return .unknown }
        if settings.heatProtection {
            guard let temperature = snapshot.temperature else { return .unknown }
            if temperature >= settings.heatStop || (previous == .heatHold && temperature > settings.heatResume) { return .heatHold }
        }
        if percent >= settings.upper { return .hold }
        if percent < settings.lower { return .charge }
        return previous == .charge ? .charge : .hold
    }
}
