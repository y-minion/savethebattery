import Foundation
/// One local calendar day of time-weighted battery usage. Durations are seconds.
public struct DailyUsage: Codable, Equatable, Sendable {
    public var day: Date
    public var observed = 0.0, onAC = 0.0
    public var soc90 = 0.0, soc95 = 0.0, socSeconds = 0.0, socSum = 0.0
    public var hot35 = 0.0, hot40 = 0.0, hot35OnAC = 0.0
    public var maxTemperature: Double?
    public var stressSeconds = 0.0, stress = 0.0, stressAt80 = 0.0
    public var health: Double?
    public var cycles: Int?
    public var designCapacity: Int?
    public var batteryID: String?
    public init(day: Date) { self.day = day }
    /// Missing keys fall back to defaults so files written by older or newer versions keep their history.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v(_ k: CodingKeys) throws -> Double { try c.decodeIfPresent(Double.self, forKey: k) ?? 0 }
        day = try c.decode(Date.self, forKey: .day)
        observed = try v(.observed); onAC = try v(.onAC)
        soc90 = try v(.soc90); soc95 = try v(.soc95); socSeconds = try v(.socSeconds); socSum = try v(.socSum)
        hot35 = try v(.hot35); hot40 = try v(.hot40); hot35OnAC = try v(.hot35OnAC)
        maxTemperature = try c.decodeIfPresent(Double.self, forKey: .maxTemperature)
        stressSeconds = try v(.stressSeconds); stress = try v(.stress); stressAt80 = try v(.stressAt80)
        health = try c.decodeIfPresent(Double.self, forKey: .health)
        cycles = try c.decodeIfPresent(Int.self, forKey: .cycles)
        designCapacity = try c.decodeIfPresent(Int.self, forKey: .designCapacity)
        batteryID = try c.decodeIfPresent(String.self, forKey: .batteryID)
    }
    public var averageSoC: Double? { socSeconds > 0 ? socSum / socSeconds : nil }
}
public enum HealthLedger {
    public static let maxGap: TimeInterval = 300
    /// Day records kept, counted rather than dated so a wrong clock cannot prune real history.
    public static let retentionDays = 400
    /// Adds the interval since `previous` (state of the earlier sample), split at local midnight.
    /// Gaps over five minutes stay unknown. A sample older than `previous` means the clock went back:
    /// it is ignored and days recorded after its day (from the wrong clock) are dropped.
    public static func record(_ sample: BatterySnapshot, after previous: BatterySnapshot?, into days: [DailyUsage], calendar: Calendar) -> [DailyUsage] {
        var days = days
        if let p = previous {
            if sample.timestamp < p.timestamp {
                let today = calendar.startOfDay(for: sample.timestamp)
                days.removeAll { $0.day > today }
                return days
            }
            var start = p.timestamp
            if sample.timestamp.timeIntervalSince(start) <= maxGap {
                while start < sample.timestamp {
                    let dayStart = calendar.startOfDay(for: start)
                    let stop = min(sample.timestamp, calendar.date(byAdding: .day, value: 1, to: dayStart)!)
                    let i = slot(dayStart, &days)
                    accumulate(p, seconds: stop.timeIntervalSince(start), into: &days[i])
                    start = stop
                }
            }
        }
        let i = slot(calendar.startOfDay(for: sample.timestamp), &days)
        if let v = sample.healthPrecise { days[i].health = v }
        if let v = sample.cycles { days[i].cycles = v }
        if let v = sample.designCapacity { days[i].designCapacity = v }
        if let v = sample.batteryID { days[i].batteryID = v }
        if days.count > retentionDays { days.removeFirst(days.count - retentionDays) }
        return days
    }
    static func slot(_ day: Date, _ days: inout [DailyUsage]) -> Int {
        if let i = days.lastIndex(where: { $0.day == day }) { return i }
        days.append(DailyUsage(day: day)); days.sort { $0.day < $1.day }
        return days.firstIndex { $0.day == day }!
    }
    static func accumulate(_ s: BatterySnapshot, seconds dt: Double, into d: inout DailyUsage) {
        d.observed += dt
        if s.onAC { d.onAC += dt }
        let soc = s.percent.map(Double.init)
        if let p = soc {
            d.socSeconds += dt; d.socSum += p * dt
            if p >= 90 { d.soc90 += dt }
            if p >= 95 { d.soc95 += dt }
        }
        if let t = s.temperature {
            if t >= 35 { d.hot35 += dt }
            if t >= 40 { d.hot40 += dt }
            if t >= 35, s.onAC { d.hot35OnAC += dt }
            d.maxTemperature = max(d.maxTemperature ?? t, t)
            if let p = soc {
                d.stressSeconds += dt
                d.stress += StressModel.rate(soc: p, temperature: t) * dt
                d.stressAt80 += StressModel.rate(soc: min(p, 80), temperature: t) * dt
            }
        }
    }
}
public enum BatterySegment {
    /// Days since the most recent battery replacement: a different identifier or design capacity, or a falling cycle count.
    public static func current(_ days: [DailyUsage]) -> [DailyUsage] {
        guard var start = days.indices.last else { return [] }
        var id = days[start].batteryID, design = days[start].designCapacity, cycles = days[start].cycles
        while start > 0 {
            let d = days[start - 1]
            if let a = d.batteryID, let b = id, a != b { break }
            if let a = d.designCapacity, let b = design, a != b { break }
            if let a = d.cycles, let b = cycles, a > b { break }
            id = d.batteryID ?? id; design = d.designCapacity ?? design; cycles = d.cycles ?? cycles
            start -= 1
        }
        return Array(days[start...])
    }
}
