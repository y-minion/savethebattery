import Foundation
public enum TrendStatus: Codable, Equatable, Sendable {
    case collecting(days: Int, points: Int)
    case alreadyBelow
    case notDeclining
    case beyondHorizon
    case projected(earliest: Date, latest: Date?)
}
public struct CycleProjection: Codable, Equatable, Sendable { public var low: Int; public var high: Int? }
/// Measured-only health trend. Robust Theil–Sen fit; the range comes from the 25th and 75th percentile pair slopes.
public struct HealthTrend: Codable, Equatable, Sendable {
    public var status: TrendStatus
    public var cycles: CycleProjection?
    public init(status: TrendStatus, cycles: CycleProjection? = nil) { self.status = status; self.cycles = cycles }
    public static let threshold = 80.0, minDays = 30, minPoints = 5, minChange = 1.0, horizonDays = 15 * 365
    public static func make(_ days: [DailyUsage], now: Date, calendar: Calendar) -> HealthTrend {
        let points = days.compactMap { d in d.health.map { (day: d.day, health: $0) } }
        guard let first = points.first, let last = points.last else { return HealthTrend(status: .collecting(days: 0, points: 0)) }
        if last.health <= threshold { return HealthTrend(status: .alreadyBelow) }
        let span = calendar.dateComponents([.day], from: first.day, to: last.day).day ?? 0
        let ys = points.map(\.health)
        guard span >= minDays, points.count >= minPoints, ys.max()! - ys.min()! >= minChange else {
            return HealthTrend(status: .collecting(days: span, points: points.count))
        }
        let xy = points.map { (x: Double(calendar.dateComponents([.day], from: first.day, to: $0.day).day ?? 0), y: $0.health) }
        guard let mid = TheilSen.fit(xy, quantile: 0.5), mid.slope < 0 else { return HealthTrend(status: .notDeclining) }
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: now)!
        func reach(_ q: Double) -> Date? {
            guard let f = TheilSen.fit(xy, quantile: q), f.slope < 0 else { return nil }
            let x = min((threshold - f.intercept) / f.slope, Double(horizonDays * 4))
            return max(calendar.date(byAdding: .day, value: Int(x.rounded()), to: first.day)!, now)
        }
        guard let early = reach(0.25), early <= horizon else { return HealthTrend(status: .beyondHorizon, cycles: cycleProjection(days)) }
        let late = reach(0.75).flatMap { $0 <= horizon ? $0 : nil }
        return HealthTrend(status: .projected(earliest: early, latest: late), cycles: cycleProjection(days))
    }
    static func cycleProjection(_ days: [DailyUsage]) -> CycleProjection? {
        let xy = days.compactMap { d -> (x: Double, y: Double)? in guard let c = d.cycles, let h = d.health else { return nil }; return (Double(c), h) }
        let cycles = Set(xy.map(\.x))
        guard cycles.count >= minPoints, let lo = cycles.min(), let hi = cycles.max(), hi - lo >= 10 else { return nil }
        func reach(_ q: Double) -> Int? {
            guard let f = TheilSen.fit(xy, quantile: q), f.slope < 0 else { return nil }
            let x = (threshold - f.intercept) / f.slope
            return x <= 10000 ? max(Int(x.rounded()), Int(hi)) : nil
        }
        guard let low = reach(0.25) else { return nil }
        return CycleProjection(low: low, high: reach(0.75))
    }
}
enum TheilSen {
    struct Fit { var slope: Double; var intercept: Double }
    static func fit(_ p: [(x: Double, y: Double)], quantile q: Double) -> Fit? {
        var slopes: [Double] = []
        for i in p.indices { for j in p.indices where j > i && p[j].x != p[i].x { slopes.append((p[j].y - p[i].y) / (p[j].x - p[i].x)) } }
        guard !slopes.isEmpty else { return nil }
        let m = percentile(slopes.sorted(), q)
        return Fit(slope: m, intercept: percentile(p.map { $0.y - m * $0.x }.sorted(), 0.5))
    }
    static func percentile(_ s: [Double], _ q: Double) -> Double {
        let pos = q * Double(s.count - 1), lo = Int(pos.rounded(.down)), hi = min(lo + 1, s.count - 1)
        return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
    }
}
