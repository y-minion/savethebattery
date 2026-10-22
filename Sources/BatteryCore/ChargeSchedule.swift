import Foundation
/// What a schedule does at its time. Each maps to one charge command.
public enum ScheduleAction: Codable, Equatable, Sendable {
    case setLimit(Int), topUp, clearLimit
    public var command:ChargeCommand {
        switch self {
        case .setLimit(let p):return .setLimit(p)
        case .topUp:return .startTopUp
        case .clearLimit:return .clearLimit
        }
    }
}
/// A weekly charge schedule in the Mac's local time.
public struct ChargeScheduleRule: Codable, Equatable, Identifiable, Sendable {
    public var id:UUID;public var name:String
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday.
    public var weekdays:Set<Int>
    public var hour:Int;public var minute:Int
    public var action:ScheduleAction;public var enabled:Bool
    /// Occurrences before this moment never run, so a new or changed rule does not fire for a time already past.
    public var activeSince:Date
    public init(id:UUID=UUID(),name:String,weekdays:Set<Int>,hour:Int,minute:Int,action:ScheduleAction,enabled:Bool=true,activeSince:Date) {
        self.id=id;self.name=name;self.weekdays=weekdays;self.hour=hour;self.minute=minute;self.action=action;self.enabled=enabled;self.activeSince=activeSince
    }
    public var isValid:Bool {
        !weekdays.isEmpty && weekdays.allSatisfy { (1...7).contains($0) } && (0..<24).contains(hour) && (0..<60).contains(minute) && action.command.isValid
    }
    public mutating func edited(now:Date) { activeSince=now }
    public static func templates(now:Date) -> [ChargeScheduleRule] {
        [ChargeScheduleRule(name:"밤에는 70%",weekdays:Set(1...7),hour:22,minute:0,action:.setLimit(70),activeSince:now),
         ChargeScheduleRule(name:"평일 아침 완충",weekdays:Set(2...6),hour:7,minute:0,action:.topUp,activeSince:now),
         ChargeScheduleRule(name:"주말엔 80%",weekdays:[1,7],hour:0,minute:0,action:.setLimit(80),activeSince:now)]
    }
}
public struct ScheduleOccurrence: Equatable, Sendable {
    public var rule:ChargeScheduleRule;public var at:Date
    public init(rule:ChargeScheduleRule,at:Date) { self.rule=rule;self.at=at }
}
public enum ScheduleDecision: Equatable, Sendable { case none, run(ScheduleOccurrence), skip(ScheduleOccurrence) }
public enum SchedulePolicy {
    /// Missed occurrences older than this are skipped, so a Mac that was off for days does not start a stale top-up.
    public static let catchUpWindow:TimeInterval=43_200
    public static let maxRules=10
    public static func next(_ r:ChargeScheduleRule,after:Date,calendar:Calendar) -> Date? {
        r.weekdays.compactMap { day -> Date? in
            let match=DateComponents(hour:r.hour,minute:r.minute,weekday:day)
            guard let d=calendar.nextDate(after:after,matching:match,matchingPolicy:.nextTime) else { return nil }
            // When clocks fall back the same local time comes twice; only the first one counts.
            return isRepeat(d,r,calendar) ? calendar.nextDate(after:d,matching:match,matchingPolicy:.nextTime):d
        }.min()
    }
    private static func isRepeat(_ d:Date,_ r:ChargeScheduleRule,_ calendar:Calendar) -> Bool {
        let tz=calendar.timeZone
        let shift=tz.daylightSavingTimeOffset(for:d.addingTimeInterval(-7200))-tz.daylightSavingTimeOffset(for:d)
        guard shift>0 else { return false }
        let earlier=d.addingTimeInterval(-shift),c=calendar.dateComponents([.hour,.minute],from:earlier)
        return c.hour==r.hour && c.minute==r.minute && calendar.isDate(earlier,inSameDayAs:d)
    }
    public static func nextAny(_ rules:[ChargeScheduleRule],after:Date,calendar:Calendar) -> ScheduleOccurrence? {
        var best:ScheduleOccurrence?
        for r in rules where r.enabled && r.isValid {
            if let d=next(r,after:max(after,r.activeSince),calendar:calendar),best.map({ d<$0.at }) ?? true { best=ScheduleOccurrence(rule:r,at:d) }
        }
        return best
    }
    /// The latest occurrence since the last check; schedules override each other, so only the most recent one matters.
    public static func due(_ rules:[ChargeScheduleRule],lastCheck:Date?,now:Date,calendar:Calendar) -> ScheduleDecision {
        guard let lastCheck,lastCheck<=now else { return .none }
        var latest:ScheduleOccurrence?
        for r in rules where r.enabled && r.isValid {
            // Every rule repeats within a week, so the latest occurrence is never earlier than eight days back.
            var cursor=max(lastCheck,r.activeSince,now-8*86_400)
            var last:Date?
            while let d=next(r,after:cursor,calendar:calendar),d<=now { last=d;cursor=d }
            // Ties go to the later rule in the list.
            if let last,latest.map({ last>=$0.at }) ?? true { latest=ScheduleOccurrence(rule:r,at:last) }
        }
        guard let latest else { return .none }
        return now.timeIntervalSince(latest.at)>catchUpWindow ? .skip(latest):.run(latest)
    }
}
public enum ScheduleText {
    private static let order=[2,3,4,5,6,7,1],names=[1:"일",2:"월",3:"화",4:"수",5:"목",6:"금",7:"토"]
    public static func days(_ d:Set<Int>) -> String {
        if d==Set(1...7) { return "매일" }
        if d==Set(2...6) { return "평일" }
        if d==[1,7] { return "주말" }
        return order.filter(d.contains).compactMap { names[$0] }.joined(separator:"·")
    }
    public static func action(_ a:ScheduleAction) -> String {
        switch a {
        case .setLimit(let p):return "상한 \(p)%"
        case .topUp:return "한 번 완충"
        case .clearLimit:return "상한 끄기"
        }
    }
    /// "오늘 22:00", "내일 07:00" or "10월 26일 00:00".
    public static func when(_ d:Date,now:Date,calendar:Calendar) -> String {
        let c=calendar.dateComponents([.month,.day,.hour,.minute],from:d)
        let time=String(format:"%02d:%02d",c.hour ?? 0,c.minute ?? 0)
        if calendar.isDate(d,inSameDayAs:now) { return "오늘 \(time)" }
        if let t=calendar.date(byAdding:.day,value:1,to:now),calendar.isDate(d,inSameDayAs:t) { return "내일 \(time)" }
        return "\(c.month ?? 0)월 \(c.day ?? 0)일 \(time)"
    }
    static let templateNames:Set<String>=["밤에는 70%","평일 아침 완충","주말엔 80%"]
    /// A name the user never typed: empty, the generated sentence, or a template's; it follows the rule when edited.
    public static func isAutoName(_ name:String,for r:ChargeScheduleRule) -> Bool { name.isEmpty || name==sentence(r) || templateNames.contains(name) }
    public static func sentence(_ r:ChargeScheduleRule) -> String { "\(days(r.weekdays)) \(String(format:"%02d:%02d",r.hour,r.minute)) · \(action(r.action))" }
}
/// Decodes each element on its own so one damaged schedule does not lose the others.
struct LossyElement<T:Decodable>:Decodable {
    let value:T?
    init(from decoder:Decoder) throws { value=try? T(from:decoder) }
}
