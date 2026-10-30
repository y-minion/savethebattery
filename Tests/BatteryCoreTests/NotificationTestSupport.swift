import Foundation
@testable import BatteryCore
enum NT {
    /// Monday 2026-09-21 14:13:20 UTC, ISO week 2026-W39.
    static let t0=Date(timeIntervalSince1970:1_790_000_000)
    static var utc:Calendar { var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:"UTC")!;return c }
    static var flags:[WritableKeyPath<NotificationSettings,Bool>] { [\.limitReached,\.topUpDone,\.lowBattery,\.limitChanged,\.controlUnavailable,\.highTemperature,\.conflict,\.heatProblem,\.heatActivity,\.sessionEnded,\.sessionCancelled,\.protectionReleased,\.sleepDrain,\.suggestions,\.weeklySummary] }
    static var all:NotificationSettings { var s=NotificationSettings();for k in flags { s[keyPath:k]=true };return s }
    /// A battery at `percent`, limit 80% written by Save the Battery.
    static func input(_ dt:Double,percent:Int?=60,onAC:Bool=true,charging:Bool=false,temp:Double?=30) -> NotificationInput {
        var b=BatterySnapshot();b.timestamp=t0+dt;b.percent=percent;b.onAC=onAC;b.charging=charging;b.temperature=temp
        var i=NotificationInput(now:t0+dt,battery:b)
        i.limit=ChargeLimitState(supported:true,enabled:true,limit:80);i.lastWritten=80;i.calendar=utc
        return i
    }
    /// Evaluates inputs in order, carrying memory.
    static func run(_ inputs:[NotificationInput],_ s:NotificationSettings=all,memory:NotificationMemory=NotificationMemory()) -> [NotificationOutcome] {
        var m=memory;var out:[NotificationOutcome]=[]
        for i in inputs { let o=NotificationPolicy.evaluate(i,settings:s,memory:m);m=o.memory;out.append(o) }
        return out
    }
    static func ids(_ o:[NotificationOutcome]) -> [[String]] { o.map { $0.events.map(\.id) } }
}
