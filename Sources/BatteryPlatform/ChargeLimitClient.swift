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
        guard ChargeSupport.current else { return ChargeLimitState(supported:false) }
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
    /// Why the limit is what it is now. VibeBattery's own last change is shown only while it still explains the current value.
    public static func currentReason(record:ChargeRecord,state:ChargeLimitState,now:Date,calendar:Calendar) -> String? {
        let mine=record.lastChange.map { reason($0,now:now,calendar:calendar) }
        if record.topUpRequested != nil { return mine }
        switch state.origin(lastWritten:record.lastWritten) {
        case .vibeBattery:return mine
        case .external:return tr("Changed by another app or System Settings","다른 앱 또는 시스템 설정에서 바뀜")
        case .none:return record.lastChange?.command=="clearLimit" ? mine:tr("Turned off by another app or System Settings","다른 앱 또는 시스템 설정에서 꺼짐")
        case .unknown:return nil
        }
    }
    /// "22:00 · Schedule '70% at night' · Limit 70%" for the change log.
    public static func logLine(_ w:ChargeWrite,now:Date,calendar:Calendar) -> String {
        let who:String
        switch w.source {
        case .user:who=tr("Manual","직접")
        case .schedule:who=tr("Schedule '\(w.detail ?? "")'","일정 '\(w.detail ?? "")'")
        case .cli:who=tr("Command line","명령줄")
        case .shortcut:who=tr("Shortcut","단축어")
        case .heat:who=tr("Heat hold","과열 보류")
        case .topUp:who=tr("Restored after top-up","완충 후 복원")
        case .quit:who=tr("Restored on quit","앱 종료 시 복원")
        }
        let action:String
        switch w.command {
        case "clearLimit":action=tr("Limit off","상한 끄기")
        case "startTopUp":action=tr("Top-up started","한 번 완충 시작")
        case "endTopUp":action=tr("Top-up ended","완충 종료")
        default:
            if w.command.hasPrefix("setLimit("),let p=Int(w.command.dropFirst(9).dropLast()) { action=tr("Limit \(p)%","상한 \(p)%") } else { action=w.command }
        }
        return "\(stamp(w.date,now:now,calendar:calendar)) · \(who) · \(action)\(w.ok ? "":tr(" · failed"," · 실패"))"
    }
    static func stamp(_ d:Date,now:Date,calendar:Calendar) -> String {
        let f=DateFormatter();f.calendar=calendar;f.timeZone=calendar.timeZone;f.locale=AppLanguage.current.locale
        let day:String
        if calendar.isDate(d,inSameDayAs:now) { day="" }
        else if let y=calendar.date(byAdding:.day,value:-1,to:now),calendar.isDate(d,inSameDayAs:y) { day=tr("Yesterday ","어제 ") }
        else { f.dateFormat=tr("MMM d ","M월 d일 ");day=f.string(from:d) }
        f.dateFormat="HH:mm"
        return day+f.string(from:d)
    }
    /// "22:00 Changed by schedule '70% at night'": when and why the limit last changed.
    public static func reason(_ w:ChargeWrite,now:Date,calendar:Calendar) -> String {
        let cause:String
        switch w.source {
        case .user:cause=tr("Changed manually","직접 바꿈")
        case .schedule:cause=tr("Changed by schedule '\(w.detail ?? "")'","일정 '\(w.detail ?? "")'에 따라 바뀜")
        case .cli:cause=tr("Changed by command line","명령줄로 바뀜")
        case .shortcut:cause=tr("Changed by shortcut","단축어로 바뀜")
        case .heat:cause=tr("Changed by heat hold","과열 보류로 바뀜")
        case .topUp:cause=tr("Restored to the original limit after top-up","완충 후 원래 상한으로 복원")
        case .quit:cause=tr("Restored on quit","앱 종료 시 복원")
        }
        return "\(stamp(w.date,now:now,calendar:calendar)) \(cause)"
    }
    public static func limit(_ s:ChargeLimitState,platformAllows:Bool=ChargeSupport.current) -> String {
        if s.supported==false { return ChargeSupport.unsupportedText(platformAllows:platformAllows) }
        if s.enabled==false { return tr("Limit off (charges to 100%)","상한 꺼짐 (100%까지 충전)") }
        return s.limit.map { tr("Current limit \($0)%","현재 상한 \($0)%") } ?? tr("Limit unknown","상한 알 수 없음")
    }
}
