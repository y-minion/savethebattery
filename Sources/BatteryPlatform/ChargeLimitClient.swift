import Foundation
import BatteryCore
import MacBridge
public protocol ChargeLimitBackend {
    func read() -> ChargeLimitState
    func perform(_ c:ChargeCommand) -> Bool
}
public struct PowerUIChargeBackend: ChargeLimitBackend {
    public init() {}
    public func read() -> ChargeLimitState {
        var raw=VBChargeLimit(supported:-1,enabled:-1,limit:-1);_=vb_mcl_read(&raw)
        func flag(_ v:Int32) -> Bool? { v<0 ? nil:v==1 }
        return ChargeLimitState(supported:flag(raw.supported),enabled:flag(raw.enabled),limit:raw.limit<0 ? nil:Int(raw.limit))
    }
    public func perform(_ c:ChargeCommand) -> Bool {
        switch c {
        case .setLimit(let p):return vb_mcl_set_limit(Int32(p))==0
        case .clearLimit:return vb_mcl_disable()==0
        case .startTopUp:return vb_mcl_top_up()==0
        case .endTopUp:return vb_mcl_enable()==0
        }
    }
}
public enum ChargeText {
    public static func limit(_ s:ChargeLimitState) -> String {
        if s.supported==false { return "이 Mac에서 지원 안 됨" }
        if s.enabled==false { return "상한 꺼짐 (100%까지 충전)" }
        return s.limit.map { "현재 상한 \($0)%" } ?? "상한 알 수 없음"
    }
}
