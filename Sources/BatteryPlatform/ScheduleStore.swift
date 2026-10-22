import Foundation
import BatteryCore
/// One schedule outcome, shown under "최근 실행".
public struct ScheduleRun: Codable, Equatable {
    public enum Result: Codable, Equatable { case ran, failed(String), skipped }
    public var date:Date;public var ruleName:String;public var action:String;public var result:Result
    public init(date:Date,ruleName:String,action:String,result:Result) { self.date=date;self.ruleName=ruleName;self.action=action;self.result=result }
}
public struct ScheduleState: Codable, Equatable {
    public var lastCheck:Date?
    public var recent:[ScheduleRun]=[]
    public static let recentLimit=10
    public init() {}
}
/// Runs at most one due schedule per check. `apply` returns nil on success or the failure message.
public final class ScheduleRunner {
    private let file:JSONFile<ScheduleState>
    private let apply:(ChargeCommand,ChargeScheduleRule) -> String?
    public private(set) var state:ScheduleState
    public init(file:JSONFile<ScheduleState>,apply:@escaping (ChargeCommand,ChargeScheduleRule) -> String?) {
        self.file=file;self.apply=apply;state=file.load() ?? ScheduleState()
    }
    @discardableResult public func check(_ rules:[ChargeScheduleRule],now:Date,calendar:Calendar) -> ScheduleRun? {
        if let last=state.lastCheck,last>now { state.lastCheck=now;save();return nil }
        let decision=SchedulePolicy.due(rules,lastCheck:state.lastCheck,now:now,calendar:calendar)
        // Saved before applying, so a slow write cannot let the next check run the same occurrence again.
        state.lastCheck=now;save()
        let run:ScheduleRun
        switch decision {
        case .none:return nil
        case .skip(let o):run=ScheduleRun(date:now,ruleName:o.rule.name,action:ScheduleText.action(o.rule.action),result:.skipped)
        case .run(let o):
            let failure=apply(o.rule.action.command,o.rule)
            run=ScheduleRun(date:now,ruleName:o.rule.name,action:ScheduleText.action(o.rule.action),result:failure.map { .failed($0) } ?? .ran)
        }
        state.recent.append(run)
        if state.recent.count>ScheduleState.recentLimit { state.recent.removeFirst(state.recent.count-ScheduleState.recentLimit) }
        save()
        return run
    }
    private func save() { try? file.save(state) }
}
