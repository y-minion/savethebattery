import Foundation
public enum NotificationText {
    public static func duration(_ seconds:TimeInterval) -> String {
        let m=max(0,Int((seconds/60).rounded()))
        if m<60 { return "\(m)분" }
        return m%60==0 ? "\(m/60)시간":"\(m/60)시간 \(m%60)분"
    }
}
