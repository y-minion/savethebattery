import Foundation
public enum NotificationText {
    public static func duration(_ seconds:TimeInterval) -> String {
        let m=max(0,Int((seconds/60).rounded()))
        if m<60 { return "\(m)분" }
        return m%60==0 ? "\(m/60)시간":"\(m/60)시간 \(m%60)분"
    }
    static func limitReached(_ l:Int) -> (String,String) { ("충전 상한 \(l)% 도달","충전을 멈췄습니다. 어댑터를 연결해 두어도 괜찮습니다.") }
    static func topUpDone(_ p:Int) -> (String,String) { ("완충 끝남 · \(p)%","오래 연결해 두면 배터리에 부담이 됩니다. 원래 상한으로 돌아가는 시점은 macOS가 정합니다.") }
    static func lowBattery(_ p:Int,at:Int) -> (String,String) { ("배터리 \(p)%","설정한 \(at)% 이하로 내려갔습니다.") }
    static func limitChanged(_ l:Int?) -> (String,String) {
        guard let l else { return ("충전 상한이 꺼졌습니다","VibeBattery가 설정한 상한이 해제되어 100%까지 충전됩니다. 대시보드에서 다시 적용하세요.") }
        return ("충전 상한이 \(l)%로 바뀌었습니다","VibeBattery가 설정하지 않은 값입니다. macOS 설정이나 다른 앱이 바꿨을 수 있습니다.")
    }
    static let controlUnavailable=("충전 상한을 제어할 수 없습니다","이 macOS에서 충전 상한 기능을 찾지 못했습니다. 업데이트 후라면 GitHub에서 호환성을 확인하세요.")
    static func hot(_ t:Double,onAC:Bool) -> (String,String) {
        (String(format:"배터리 %.1f°C",t),onAC ? "충전 중 온도가 높습니다. 통풍이 되는 곳에 두거나 과열 시 충전 보류를 켜 보세요.":"배터리 온도가 높습니다. 무거운 작업을 줄이고 통풍이 되는 곳에 두세요.")
    }
    static func conflict(_ names:[String]) -> (String,String) { ("다른 충전 관리 앱 감지","\(names.joined(separator:", "))이(가) 감지되어 VibeBattery는 충전 설정을 바꾸지 않습니다.") }
    static func heatStuck(_ l:Int) -> (String,String) { ("과열 보류 복원 실패","충전 상한이 \(l)%로 남아 있습니다. 설정에서 상태를 확인하고 상한을 다시 적용하세요.") }
    static let heatPaused=("과열 보류 멈춤","다른 곳에서 충전 상한이 바뀌어 보류를 멈췄습니다. 설정에서 다시 켜면 재개합니다.")
    static let heatFailed=("과열 보류 실패","충전 상한을 낮추지 못했습니다. 설정에서 상태를 확인하세요.")
    static let heatSensor=("과열 보류가 동작하지 않습니다","배터리 온도를 10분 넘게 읽지 못했습니다.")
    static func heatHeld(_ p:Int) -> (String,String) { ("과열 보류 시작","배터리가 식을 때까지 충전 상한을 \(p)%로 낮췄습니다.") }
    static let heatRestored=("과열 보류 해제","배터리가 식어 원래 충전 상한으로 되돌렸습니다.")
}
