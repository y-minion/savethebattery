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
}
