import Foundation
public struct SleepEvent: Codable, Equatable, Sendable {
    public var start: Date, end: Date
    public var startPercent: Int?, endPercent: Int?
    public var onAC: Bool
    public static let minimumDuration: TimeInterval = 3600, highDrain = 1.0
    public init(before: BatterySnapshot, after: BatterySnapshot) {
        start = before.timestamp; end = after.timestamp; startPercent = before.percent; endPercent = after.percent; onAC = before.onAC || after.onAC
    }
    /// Percent per hour on battery; nil on adapter, for sleeps under an hour (integer percent exaggerates them) or when charge rose.
    public var drainPerHour: Double? {
        let seconds = end.timeIntervalSince(start)
        guard !onAC, seconds >= Self.minimumDuration, let a = startPercent, let b = endPercent, b <= a else { return nil }
        return Double(a - b) / (seconds / 3600)
    }
    /// High only when the rate stays above the threshold after allowing one point of integer rounding.
    public var isHigh: Bool {
        guard let r = drainPerHour else { return false }
        return r - 3600 / end.timeIntervalSince(start) > Self.highDrain
    }
}
public struct UsageSummary: Codable, Equatable, Sendable {
    public var days = 0
    public var observed = 0.0, onAC = 0.0, soc90 = 0.0, soc95 = 0.0, hot35 = 0.0, hot40 = 0.0, hot35OnAC = 0.0
    public var maxTemperature: Double?, averageSoC: Double?, averageStress: Double?
    /// Fraction of stress removed if charge never exceeded 80%.
    public var reductionAt80: Double?
    public static func make(_ days: [DailyUsage]) -> UsageSummary {
        var s = UsageSummary(); s.days = days.count
        var socSeconds = 0.0, socSum = 0.0, stressSeconds = 0.0, stress = 0.0, at80 = 0.0
        for d in days {
            s.observed += d.observed; s.onAC += d.onAC; s.soc90 += d.soc90; s.soc95 += d.soc95; s.hot35 += d.hot35; s.hot40 += d.hot40; s.hot35OnAC += d.hot35OnAC
            if let t = d.maxTemperature { s.maxTemperature = max(s.maxTemperature ?? t, t) }
            socSeconds += d.socSeconds; socSum += d.socSum; stressSeconds += d.stressSeconds; stress += d.stress; at80 += d.stressAt80
        }
        if socSeconds > 0 { s.averageSoC = socSum / socSeconds }
        if stressSeconds > 0 { s.averageStress = stress / stressSeconds }
        if stress > 0 { s.reductionAt80 = 1 - at80 / stress }
        return s
    }
}
public struct AdvisorContext: Sendable {
    /// Active charge limit, or nil when no limit is enabled.
    public var limit: Int?
    public var heatEnabled: Bool
    public init(limit: Int?, heatEnabled: Bool) { self.limit = limit; self.heatEnabled = heatEnabled }
}
public enum SuggestionKind: String, Codable, Sendable { case chargeLimit, heatHold, sleepDrain }
public struct Suggestion: Codable, Equatable, Sendable { public var kind: SuggestionKind; public var message: String }
public enum HealthAdvisor {
    public static func suggestions(week: UsageSummary, sleeps: [SleepEvent], context: AdvisorContext) -> [Suggestion] {
        var out: [Suggestion] = []
        func hours(_ s: Double) -> String { String(format: "%.1f", s / 3600) }
        if week.soc95 >= 6 * 3600, (context.limit ?? 100) > 80 {
            out.append(Suggestion(kind: .chargeLimit, message: "최근 7일 중 \(hours(week.soc95))시간을 잔량 95% 이상에서 보냈습니다. 충전 상한 80%를 권장합니다."))
        }
        if week.hot35OnAC >= 2 * 3600, !context.heatEnabled {
            out.append(Suggestion(kind: .heatHold, message: "최근 7일 중 어댑터 연결 상태로 \(hours(week.hot35OnAC))시간 동안 배터리가 35°C 이상이었습니다. 과열 보류를 켜면 이때 충전을 멈춥니다."))
        }
        if let worst = sleeps.suffix(5).filter(\.isHigh).compactMap(\.drainPerHour).max() {
            out.append(Suggestion(kind: .sleepDrain, message: String(format: "최근 잠자기 중 시간당 %.1f%% 소모가 있었습니다. 잠자기를 막는 앱이 있는지 확인하세요.", worst)))
        }
        return Array(out.prefix(3))
    }
}
public struct HealthReport: Codable, Sendable {
    public var generated: Date
    public var health: Double?, marginTo80: Double?
    public var cycles: Int?, designCycles: Int?
    public var trend: HealthTrend
    public var week: UsageSummary, month: UsageSummary
    public var sleeps: [SleepEvent]
    public var suggestions: [Suggestion]
    public static func make(snapshot: BatterySnapshot, days: [DailyUsage], sleeps: [SleepEvent], context: AdvisorContext, now: Date, calendar: Calendar, trend: HealthTrend? = nil) -> HealthReport {
        func window(_ n: Int) -> [DailyUsage] {
            let from = calendar.date(byAdding: .day, value: -(n - 1), to: calendar.startOfDay(for: now))!
            return days.filter { $0.day >= from }
        }
        let health = snapshot.healthPrecise ?? snapshot.health.map(Double.init)
        let week = UsageSummary.make(window(7))
        return HealthReport(generated: now, health: health, marginTo80: health.map { $0 - 80 }, cycles: snapshot.cycles, designCycles: snapshot.designCycles,
                            trend: trend ?? HealthTrend.make(BatterySegment.current(days), now: now, calendar: calendar), week: week, month: UsageSummary.make(window(30)),
                            sleeps: Array(sleeps.reversed()), suggestions: HealthAdvisor.suggestions(week: week, sleeps: sleeps, context: context))
    }
}
public enum HealthText {
    public static let caveat = "스트레스는 일반 리튬이온 연구(Battery University BU-808) 기반 상대값이며 이 배터리에서 검증된 값이 아닙니다."
    static func month(_ d: Date, _ calendar: Calendar) -> String { let c = calendar.dateComponents([.year, .month], from: d); return "\(c.year!)년 \(c.month!)월" }
    public static func trend(_ t: HealthTrend, calendar: Calendar) -> String {
        switch t.status {
        case .collecting(let days, let points, let change):
            if days < HealthTrend.minDays { return "데이터 수집 중 (\(days)/\(HealthTrend.minDays)일)" }
            if points < HealthTrend.minPoints { return "데이터 수집 중 (측정한 날 \(points)/\(HealthTrend.minPoints)일)" }
            return String(format: "변화가 작아 아직 추세 계산 불가 (변화 %.1f/%.1f%%p)", change, HealthTrend.minChange)
        case .alreadyBelow: return "건강도가 이미 80% 이하입니다"
        case .notDeclining: return "아직 하락 추세가 보이지 않습니다"
        case .beyondHorizon: return "80% 도달 예상: 15년 이상"
        case .projected(let e, let l): return "80% 도달 예상: \(month(e, calendar)) ~ \(l.map { month($0, calendar) } ?? "알 수 없음")"
        }
    }
    public static func stress(_ s: UsageSummary) -> String {
        guard let r = s.reductionAt80 else { return "측정 중" }
        if r < 0.005 { return "이미 80% 이하로 유지 중" }
        return "상한 80%였다면 스트레스 −\(Int((r * 100).rounded()))%"
    }
    static func hours(_ s: Double) -> String { String(format: "%.1f시간", s / 3600) }
    public static func lines(_ r: HealthReport, calendar: Calendar) -> [String] {
        var out: [String] = []
        if let h = r.health {
            var line = String(format: "건강도(추정) %.1f%%", h)
            if let c = r.cycles { line += " · 사이클 \(c)\(r.designCycles.map { "/\($0)" } ?? "")" }
            if let m = r.marginTo80 { line += m > 0 ? String(format: " · 80%%까지 %.1f%%p", m) : " · 80% 이하" }
            out.append(line)
        } else { out.append("배터리 정보 없음") }
        out.append("수명 추세: \(trend(r.trend, calendar: calendar))")
        if let p = r.trend.cycles { out.append("80% 도달 예상 사이클: \(p.low) ~ \(p.high.map(String.init) ?? "알 수 없음")") }
        let w = r.week
        out.append("최근 7일: 측정 \(hours(w.observed)) · 95% 이상 \(hours(w.soc95)) · 35°C 이상 \(hours(w.hot35))" + (w.observed > 0 ? " · 어댑터 \(Int((w.onAC / w.observed * 100).rounded()))%" : ""))
        out.append("스트레스: " + (w.averageStress.map { String(format: "평균 %.1f (25°C·잔량 40%% = 1) · ", $0) } ?? "") + stress(w))
        let measured = r.sleeps.filter { $0.drainPerHour != nil }
        if !measured.isEmpty { out.append("잠자기: 최근 \(measured.count)회 측정 · 높은 소모 \(measured.filter(\.isHigh).count)회") }
        out += r.suggestions.map { "제안: \($0.message)" }
        out.append("참고: \(caveat)")
        return out
    }
}
