import Foundation
import BatteryCore
public protocol ChargeHelperClient {
    var isInstalled:Bool { get }
    /// nil on success, otherwise a user-facing reason.
    func setLimit(_ percent:Int) -> String?
}
public enum ChargeError: Error, Equatable, LocalizedError {
    case invalid, conflict([String]), helperRequired, unavailable, rejected(String), notApplied, heatHoldActive
    public var errorDescription:String? {
        switch self {
        case .invalid:return "충전 상한은 50~100% 사이에서 5% 단위로 고를 수 있습니다."
        case .conflict(let names):return "\(names.joined(separator:", "))이(가) 충전을 관리하고 있습니다. 해당 앱을 종료하거나 삭제하면 제어할 수 있습니다."
        case .helperRequired:return "80% 미만 상한에는 VibeBattery 헬퍼 설치가 필요합니다."
        case .unavailable:return "이 macOS에서 충전 상한 제어를 확인하지 못했습니다."
        case .rejected(let m):return m
        case .notApplied:return "적용 실패: 다시 읽은 값이 요청과 다릅니다. 자동으로 재시도하지 않습니다."
        case .heatHoldActive:return "과열 보류 중에는 한 번 완충을 시작할 수 없습니다. 배터리가 식은 뒤 다시 시도하세요."
        }
    }
}
public struct ChargeRecord: Codable, Equatable {
    public var lastWritten:Int?;public var heat=HeatState();public var heatPaused=false;public var topUpRequested:Date?
    public init() {}
}
public final class ChargeController {
    private let backend:ChargeLimitBackend;private let helper:ChargeHelperClient?
    private let detect:()->[OtherChargeController];private let url:URL
    public private(set) var record:ChargeRecord
    public init(backend:ChargeLimitBackend,helper:ChargeHelperClient?,detect:@escaping ()->[OtherChargeController],url:URL) {
        self.backend=backend;self.helper=helper;self.detect=detect;self.url=url
        record=(try? JSONDecoder().decode(ChargeRecord.self,from:Data(contentsOf:url))) ?? ChargeRecord()
    }
    public var helperInstalled:Bool { helper?.isInstalled==true }
    public func state() -> ChargeLimitState { backend.read() }
    @discardableResult public func apply(_ c:ChargeCommand,byUser:Bool=true) -> Result<ChargeLimitState,ChargeError> {
        guard c.isValid else { return .failure(.invalid) }
        let others=detect();guard others.isEmpty else { return .failure(.conflict(others.map(\.name))) }
        guard backend.read().supported==true else { return .failure(.unavailable) }
        if c == .startTopUp,record.heat.holdLimit != nil { return .failure(.heatHoldActive) }
        defer { save() }
        if case .setLimit(let p)=c,c.requiresHelper {
            guard let helper,helper.isInstalled else { return .failure(.helperRequired) }
            if let m=helper.setLimit(p) { return .failure(.rejected(m)) }
        } else if !backend.perform(c) { return .failure(.rejected("macOS가 요청을 거부했습니다.")) }
        let s=backend.read()
        guard s.matches(c) != false else { return .failure(.notApplied) }
        // A user's own successful choice replaces any hold; a failed one keeps it.
        if byUser { record.heat=HeatState();record.heatPaused=false }
        switch c {
        case .setLimit(let p):record.lastWritten=p
        case .clearLimit:record.lastWritten=nil
        case .startTopUp:record.topUpRequested=Date()
        case .endTopUp:record.topUpRequested=nil
        }
        return .success(s)
    }
    public func heatStep(snapshot:BatterySnapshot,settings:HeatSettings,now:Date=Date()) -> (action:HeatAction,result:Result<ChargeLimitState,ChargeError>?) {
        guard !record.heatPaused,detect().isEmpty else { return (.none,nil) }
        let before=record.heat;var h=before
        let a=HeatHoldPolicy.step(snapshot:snapshot,limit:backend.read(),settings:settings,state:&h,helperAvailable:helperInstalled,now:now)
        record.heat=h;save()
        let command:ChargeCommand
        switch a {
        case .hold(let p):command = .setLimit(p)
        case .restore(let c):command=c
        case .yielded:
            // Someone else changed the limit; stop automating until the user re-enables.
            record.heatPaused=true;save();return (a,nil)
        default:return (a,nil)
        }
        let r=apply(command,byUser:false)
        // A failed automatic write must not repeat every refresh. A failed restore
        // keeps the hold so the lowered limit and the user's value stay visible.
        if case .failure=r {
            if case .restore=a { record.heat=before } else { record.heat=HeatState() }
            record.heatPaused=true;save()
        }
        return (a,r)
    }
    /// Restores the user's limit when the app quits during a hold, unless someone else changed it.
    @discardableResult public func releaseHold() -> Result<ChargeLimitState,ChargeError>? {
        guard let hold=record.heat.holdLimit else { return nil }
        let s=backend.read()
        guard s.enabled==true,s.limit==hold else { record.heat=HeatState();save();return nil }
        let r=apply(record.heat.userLimit.map { .setLimit($0) } ?? .clearLimit,byUser:false)
        if case .success=r { record.heat=HeatState();save() }
        return r
    }
    public func resumeHeat() { record.heatPaused=false;save() }
    private func save() {
        try? FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try? JSONEncoder().encode(record).write(to:url,options:[.atomic])
    }
}
