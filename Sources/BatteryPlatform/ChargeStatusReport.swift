import Foundation
import BatteryCore
extension ChargeCLI {
    /// 0 success, 1 not applied or result unknown, 3 app not running (2 is a usage error, decided before sending).
    public static func exitCode(_ r:Result<ControlResponse,ControlClient.Failure>) -> Int32 {
        switch r {
        case .success(let response):return response.ok ? 0:1
        case .failure(.timedOut):return 1
        case .failure(.notRunning):return 3
        }
    }
    public static func message(_ r:Result<ControlResponse,ControlClient.Failure>) -> String {
        switch r {
        case .success(let response):return HelperReply.display(response.message) ?? response.message
        case .failure(.timedOut):return tr("Could not confirm the result. Check with vbctl charge status","결과를 확인하지 못했습니다. vbctl charge status로 확인하세요")
        case .failure(.notRunning):return tr("VibeBattery must be running. Open the app and try again.","VibeBattery 앱이 실행 중이어야 합니다. 앱을 열고 다시 시도하세요.")
        }
    }
}
/// `vbctl charge status --json`. The first three keys are the original output and stay unchanged.
public struct ChargeStatusReport: Codable, Equatable {
    public var supported:Bool?;public var enabled:Bool?;public var limit:Int?
    public var origin:String
    public var topUpActive:Bool
    /// Only when the app is running, since schedules run only there.
    public var nextSchedule:Date?
    public static func make(state:ChargeLimitState,record:ChargeRecord?,rules:[ChargeScheduleRule],appRunning:Bool,now:Date,calendar:Calendar) -> ChargeStatusReport {
        ChargeStatusReport(supported:state.supported,enabled:state.enabled,limit:state.limit,
                           origin:state.origin(lastWritten:record?.lastWritten).rawValue,
                           topUpActive:record.map { $0.topUpRequested != nil && $0.topUpObservedOff } ?? false,
                           nextSchedule:appRunning ? SchedulePolicy.nextAny(rules,after:now,calendar:calendar)?.at:nil)
    }
}
