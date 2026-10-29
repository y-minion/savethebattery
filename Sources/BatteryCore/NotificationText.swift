import Foundation
public enum NotificationText {
    public static func duration(_ seconds:TimeInterval) -> String {
        let m=max(0,Int((seconds/60).rounded()))
        if m<60 { return tr("\(m) min","\(m)분") }
        return m%60==0 ? tr("\(m/60) h","\(m/60)시간"):tr("\(m/60) h \(m%60) min","\(m/60)시간 \(m%60)분")
    }
    static func limitReached(_ l:Int) -> (String,String) { (tr("Charge limit \(l)% reached","충전 상한 \(l)% 도달"),tr("Charging stopped. It is fine to leave the adapter plugged in.","충전을 멈췄습니다. 어댑터를 연결해 두어도 괜찮습니다.")) }
    static func topUpDone(_ p:Int) -> (String,String) { (tr("Top-up done · \(p)%","완충 끝남 · \(p)%"),tr("Staying plugged in for long puts stress on the battery. macOS decides when the original limit returns.","오래 연결해 두면 배터리에 부담이 됩니다. 원래 상한으로 돌아가는 시점은 macOS가 정합니다.")) }
    static func lowBattery(_ p:Int,at:Int) -> (String,String) { (tr("Battery \(p)%","배터리 \(p)%"),tr("Dropped to \(at)% or below, as you set.","설정한 \(at)% 이하로 내려갔습니다.")) }
    static func limitChanged(_ l:Int?) -> (String,String) {
        guard let l else { return (tr("Charge limit turned off","충전 상한이 꺼졌습니다"),tr("The limit set by Save the Battery was removed, so charging goes up to 100%. Apply it again from the dashboard.","Save the Battery가 설정한 상한이 해제되어 100%까지 충전됩니다. 대시보드에서 다시 적용하세요.")) }
        return (tr("Charge limit changed to \(l)%","충전 상한이 \(l)%로 바뀌었습니다"),tr("Save the Battery did not set this value. macOS settings or another app may have changed it.","Save the Battery가 설정하지 않은 값입니다. macOS 설정이나 다른 앱이 바꿨을 수 있습니다."))
    }
    static var controlUnavailable:(String,String) { (tr("Cannot control the charge limit","충전 상한을 제어할 수 없습니다"),tr("The charge limit feature was not found on this macOS. If you just updated, check compatibility on GitHub.","이 macOS에서 충전 상한 기능을 찾지 못했습니다. 업데이트 후라면 GitHub에서 호환성을 확인하세요.")) }
    static func hot(_ t:Double,onAC:Bool) -> (String,String) {
        (String(format:tr("Battery %.1f°C","배터리 %.1f°C"),t),onAC ? tr("The battery is hot while charging. Move it somewhere with airflow or turn on heat hold.","충전 중 온도가 높습니다. 통풍이 되는 곳에 두거나 과열 시 충전 보류를 켜 보세요."):tr("The battery is hot. Reduce heavy work and place the Mac somewhere with airflow.","배터리 온도가 높습니다. 무거운 작업을 줄이고 통풍이 되는 곳에 두세요."))
    }
    static func conflict(_ names:[String]) -> (String,String) { (tr("Another charge manager detected","다른 충전 관리 앱 감지"),tr("\(names.joined(separator:", ")) detected, so Save the Battery will not change charge settings.","\(names.joined(separator:", "))이(가) 감지되어 Save the Battery는 충전 설정을 바꾸지 않습니다.")) }
    static func heatStuck(_ l:Int) -> (String,String) { (tr("Heat hold restore failed","과열 보류 복원 실패"),tr("The charge limit is still \(l)%. Check the status in Settings and apply the limit again.","충전 상한이 \(l)%로 남아 있습니다. 설정에서 상태를 확인하고 상한을 다시 적용하세요.")) }
    static var heatPaused:(String,String) { (tr("Heat hold stopped","과열 보류 멈춤"),tr("The charge limit was changed elsewhere, so the hold stopped. Turn it on again in Settings to resume.","다른 곳에서 충전 상한이 바뀌어 보류를 멈췄습니다. 설정에서 다시 켜면 재개합니다.")) }
    static var heatFailed:(String,String) { (tr("Heat hold failed","과열 보류 실패"),tr("Could not lower the charge limit. Check the status in Settings.","충전 상한을 낮추지 못했습니다. 설정에서 상태를 확인하세요.")) }
    static var heatSensor:(String,String) { (tr("Heat hold is not working","과열 보류가 동작하지 않습니다"),tr("The battery temperature could not be read for over 10 minutes.","배터리 온도를 10분 넘게 읽지 못했습니다.")) }
    static func heatHeld(_ p:Int) -> (String,String) { (tr("Heat hold started","과열 보류 시작"),tr("Lowered the charge limit to \(p)% until the battery cools down.","배터리가 식을 때까지 충전 상한을 \(p)%로 낮췄습니다.")) }
    static var heatRestored:(String,String) { (tr("Heat hold ended","과열 보류 해제"),tr("The battery cooled down, so the original charge limit was restored.","배터리가 식어 원래 충전 상한으로 되돌렸습니다.")) }
    static func sessionEnd(_ x:SessionSummary) -> (String,String) {
        let name=x.command.isEmpty ? tr("Task","작업"):x.command,code=x.exitCode.map { tr(" · code \($0)"," · 코드 \($0)") } ?? ""
        let result:String
        switch x.outcome {
        case .cancelled:result=tr("cancelled","취소됨")
        case .detached,.expired:result=tr("ended after protection was released","보호 해제 후 종료")+code
        default:result=x.exitCode==0 ? tr("done","완료"):tr("failed","실패")+code
        }
        return ("\(name) \(result)",tr("Took \(duration((x.ended ?? x.started).timeIntervalSince(x.started)))","걸린 시간 \(duration((x.ended ?? x.started).timeIntervalSince(x.started)))"))
    }
    static func sessionBatch(_ xs:[SessionSummary]) -> (String,String) {
        let ok=xs.filter { $0.exitCode==0 && $0.outcome != .cancelled }.count
        return (tr("\(xs.count) tasks ended","작업 \(xs.count)개 종료"),tr("Succeeded \(ok) · other \(xs.count-ok)","성공 \(ok) · 그 외 \(xs.count-ok)"))
    }
    static func protectionReleased(_ x:SessionSummary) -> (String,String) {
        let why=x.outcome == .expired ? tr("The protection time ended.","보호 시간이 끝났습니다."):tr("The adapter was unplugged.","어댑터가 분리되었습니다.")
        return (tr("\(x.command.isEmpty ? "Task":x.command) sleep prevention released","\(x.command.isEmpty ? "작업":x.command) 잠자기 방지 해제"),tr("\(why) The task continues, but the Mac may sleep.","\(why) 작업은 계속되지만 맥이 잠들 수 있습니다."))
    }
    static func sleepDrain(_ rate:Double,_ seconds:TimeInterval) -> (String,String) {
        (tr("Battery dropped a lot during sleep","잠자기 중 배터리가 많이 줄었습니다"),String(format:tr("%2$.1f%% per hour over %1$@. Check whether an app prevents or wakes sleep.","%1$@ 동안 시간당 %2$.1f%%. 잠자기를 막거나 깨우는 앱이 있는지 확인해 보세요."),duration(seconds),rate))
    }
    static func weekly(_ u:UsageSummary) -> (String,String) { (tr("Weekly battery summary","주간 배터리 요약"),tr("Last 7 days at 95% or higher: \(HealthText.hours(u.soc95)) · \(HealthText.stress(u))","최근 7일 잔량 95% 이상 \(HealthText.hours(u.soc95)) · \(HealthText.stress(u))")) }
}
