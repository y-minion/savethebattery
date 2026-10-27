import Foundation
import BatteryCore
public protocol ChargeHelperClient {
    var isInstalled:Bool { get }
    /// nil on success, otherwise a user-facing reason.
    func setLimit(_ percent:Int) -> String?
}
public enum ChargeError: Error, Equatable, LocalizedError {
    case invalid, conflict([String]), helperRequired, unavailable, rejected(String), notApplied, heatHoldActive, noTopUp
    public var errorDescription:String? {
        switch self {
        case .invalid:return tr("The charge limit can be set from 50 to 100% in steps of 5%.","충전 상한은 50~100% 사이에서 5% 단위로 고를 수 있습니다.")
        case .conflict(let names):return tr("\(names.joined(separator:", ")) is managing charging. Quit or remove that app to take control.","\(names.joined(separator:", "))이(가) 충전을 관리하고 있습니다. 해당 앱을 종료하거나 삭제하면 제어할 수 있습니다.")
        case .helperRequired:return tr("Limits below 80% need the VibeBattery helper.","80% 미만 상한에는 VibeBattery 헬퍼 설치가 필요합니다.")
        case .unavailable:return tr("Could not confirm charge limit control on this macOS.","이 macOS에서 충전 상한 제어를 확인하지 못했습니다.")
        case .rejected(let m):return m
        case .notApplied:return tr("Not applied: the value read back differs from the request. It will not retry automatically.","적용 실패: 다시 읽은 값이 요청과 다릅니다. 자동으로 재시도하지 않습니다.")
        case .noTopUp:return tr("No top-up is in progress.","진행 중인 한 번 완충이 없습니다.")
        case .heatHoldActive:return tr("Cannot start a top-up during heat hold. Try again after the battery cools down.","과열 보류 중에는 한 번 완충을 시작할 수 없습니다. 배터리가 식은 뒤 다시 시도하세요.")
        }
    }
}
/// One attempted charge write, kept so an unexpected limit change can be traced to its source.
public struct ChargeWrite: Codable, Equatable {
    public enum Source: String, Codable { case user, heat, quit, topUp, schedule, cli, shortcut }
    public var date:Date;public var command:String;public var source:Source;public var ok:Bool
    /// The schedule's name for schedule writes.
    public var detail:String?
    public init(date:Date,command:String,source:Source,ok:Bool,detail:String?=nil) { self.date=date;self.command=command;self.source=source;self.ok=ok;self.detail=detail }
}
public struct ChargeRecord: Codable, Equatable {
    public var lastWritten:Int?;public var heat=HeatState();public var heatPaused=false;public var topUpRequested:Date?
    /// Owner of the limit a hold replaced, so restoring it keeps the original origin.
    public var lastWrittenBeforeHold:Int?
    public var topUpObservedOff=false
    /// Count of writes VibeBattery attempted, so its own changes are never reported as someone else's.
    public var writes=0
    public var log:[ChargeWrite]=[]
    public static let logLimit=20
    /// The latest write that took effect, used to explain the current limit.
    public var lastChange:ChargeWrite? { log.last(where:\.ok) }
    public init() {}
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        lastWritten=try c.decodeIfPresent(Int.self,forKey:.lastWritten)
        heat=try c.decodeIfPresent(HeatState.self,forKey:.heat) ?? HeatState()
        heatPaused=try c.decodeIfPresent(Bool.self,forKey:.heatPaused) ?? false
        topUpRequested=try c.decodeIfPresent(Date.self,forKey:.topUpRequested)
        lastWrittenBeforeHold=try c.decodeIfPresent(Int.self,forKey:.lastWrittenBeforeHold)
        topUpObservedOff=try c.decodeIfPresent(Bool.self,forKey:.topUpObservedOff) ?? false
        writes=try c.decodeIfPresent(Int.self,forKey:.writes) ?? 0
        log=(try? c.decodeIfPresent([ChargeWrite].self,forKey:.log)) ?? []
    }
}
public final class ChargeController {
    private let backend:ChargeLimitBackend;private let helper:ChargeHelperClient?
    private let detect:()->[OtherChargeController];private let url:URL;private let pause:(TimeInterval)->Void
    public private(set) var record:ChargeRecord
    /// macOS applies a helper write after its domain-change notification, so read-back polls briefly.
    static let settleStep:TimeInterval=0.5,settleSteps=8
    public init(backend:ChargeLimitBackend,helper:ChargeHelperClient?,detect:@escaping ()->[OtherChargeController],url:URL,pause:@escaping (TimeInterval)->Void={ Thread.sleep(forTimeInterval:$0) }) {
        self.backend=backend;self.helper=helper;self.detect=detect;self.url=url;self.pause=pause
        record=(try? JSONDecoder().decode(ChargeRecord.self,from:Data(contentsOf:url))) ?? ChargeRecord()
    }
    public var helperInstalled:Bool { helper?.isInstalled==true }
    /// Reads the limit and ends top-up bookkeeping once macOS has turned the limit back on.
    public func state() -> ChargeLimitState {
        let s=backend.read()
        if record.topUpRequested != nil {
            if s.allowsFullCharge { record.topUpObservedOff=true }
            else if s.enabled==true,record.topUpObservedOff {
                record.topUpRequested=nil;record.topUpObservedOff=false;save()
                if case .success(let r)?=reapplyAfterTopUp(s) { return r }
            }
            save()
        }
        return s
    }
    public var topUpActive:Bool { record.topUpRequested != nil && record.topUpObservedOff }
    @discardableResult public func apply(_ c:ChargeCommand,byUser:Bool=true,source:ChargeWrite.Source?=nil,detail:String?=nil) -> Result<ChargeLimitState,ChargeError> {
        let from=source ?? (byUser ? .user:.heat)
        // Ending a top-up that is not running would turn a limit the user switched off back on.
        if c == .endTopUp,byUser,record.topUpRequested==nil { return .failure(.noTopUp) }
        // A chosen limit ends a running one-time full charge first, so the new value is not overridden when it ends.
        if byUser,record.topUpRequested != nil,c.endsTopUp {
            let e=write(.endTopUp,byUser:true);log(.endTopUp,from,detail,e)
            if case .failure=e { return e }
        }
        let r=write(c,byUser:byUser)
        log(c,from,detail,r)
        if c == .endTopUp,case .success(let s)=r,let again=reapplyAfterTopUp(s) { return again }
        return r
    }
    /// macOS re-enables the limit at its own stored value, which never holds a
    /// helper-written limit below 80%; put back the limit VibeBattery last set.
    private func reapplyAfterTopUp(_ s:ChargeLimitState) -> Result<ChargeLimitState,ChargeError>? {
        guard let want=record.lastWritten,s.enabled==true,s.limit != want else { return nil }
        return apply(.setLimit(want),byUser:false,source:.topUp)
    }
    /// Only attempts that reached macOS or the helper are logged; refusals before writing are not.
    private func log(_ c:ChargeCommand,_ source:ChargeWrite.Source,_ detail:String?,_ r:Result<ChargeLimitState,ChargeError>) {
        switch r { case .success,.failure(.notApplied),.failure(.rejected):break;default:return }
        var ok=false;if case .success=r { ok=true }
        record.log.append(ChargeWrite(date:Date(),command:"\(c)",source:source,ok:ok,detail:detail))
        if record.log.count>ChargeRecord.logLimit { record.log.removeFirst(record.log.count-ChargeRecord.logLimit) }
        save()
    }
    private func write(_ c:ChargeCommand,byUser:Bool) -> Result<ChargeLimitState,ChargeError> {
        guard c.isValid else { return .failure(.invalid) }
        let others=detect();guard others.isEmpty else { return .failure(.conflict(others.map(\.name))) }
        guard backend.read().supported==true else { return .failure(.unavailable) }
        if c == .startTopUp,record.heat.holdLimit != nil { return .failure(.heatHoldActive) }
        defer { save() }
        if case .setLimit(let p)=c,c.requiresHelper {
            guard let helper,helper.isInstalled else { return .failure(.helperRequired) }
            record.writes+=1
            if let m=helper.setLimit(p) { return .failure(.rejected(m)) }
        } else {
            record.writes+=1
            if !backend.perform(c) { return .failure(.rejected(tr("macOS rejected the request.","macOS가 요청을 거부했습니다."))) }
        }
        var s=backend.read()
        for _ in 0..<Self.settleSteps where s.matches(c)==false { pause(Self.settleStep);s=backend.read() }
        guard s.matches(c) != false else { return .failure(.notApplied) }
        // A user's own successful choice replaces any hold; a failed one keeps it.
        if byUser { record.heat=HeatState();record.heatPaused=false }
        switch c {
        case .setLimit(let p):record.lastWritten=p
        case .clearLimit:record.lastWritten=nil
        case .startTopUp:record.topUpRequested=Date();record.topUpObservedOff=false
        case .endTopUp:record.topUpRequested=nil;record.topUpObservedOff=false
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
        case .hold(let p):command = .setLimit(p);record.lastWrittenBeforeHold=record.lastWritten
        case .restore(let c):command=c
        case .yielded:
            // Someone else changed the limit; stop automating until the user re-enables.
            record.heatPaused=true;save();return (a,nil)
        default:return (a,nil)
        }
        let r=apply(command,byUser:false)
        if case .success=r,case .restore=a { record.lastWritten=record.lastWrittenBeforeHold;save() }
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
        let r=apply(record.heat.userLimit.map { .setLimit($0) } ?? .clearLimit,byUser:false,source:.quit)
        if case .success=r { record.heat=HeatState();record.lastWritten=record.lastWrittenBeforeHold;save() }
        return r
    }
    public func resumeHeat() { record.heatPaused=false;save() }
    private var saved:ChargeRecord?
    private func save() {
        guard saved != record else { return }
        saved=record
        try? FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try? JSONEncoder().encode(record).write(to:url,options:[.atomic])
    }
}
