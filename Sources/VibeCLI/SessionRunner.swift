import Foundation
import MacBridge
import BatteryCore
import BatteryPlatform
func runSession(_ options:RunOptions) throws -> Int32 {
    let store=AppPaths.sessions;let lease=PowerLease()
    try store.removeInactive(before:Date().addingTimeInterval(-30*86400))
    var record=SessionRecord();record.command=URL(fileURLWithPath:options.command[0]).lastPathComponent
    record.owner=ProcessReader.one(getpid())?.identity
    record.deadline=Date().addingTimeInterval(options.hours*3600)
    record.cleanup=options.cleanup ? .safe:.observe
    let onAC=BatteryReader.read().onAC
    if onAC || options.allowBattery { try lease.acquire(reason:"VibeBattery: \(record.command)");record.protected=true }
    defer { lease.release() }
    try store.save(record)
    note("세션 \(record.id.uuidString) · 보호 시간 \(options.hours)h · 정리 \(options.cleanup ? "허용된 리소스만" : "관찰")")
    var env=ProcessInfo.processInfo.environment;env["VIBEBATTERY_SESSION"]=record.id.uuidString
    vb_watch_signals()
    let child:ChildCommand
    do { child=try ChildCommand(options.command,environment:env) }
    catch { lease.release();record.protected=false;record.outcome = .failed;record.ended=Date();try? store.save(record);throw error }
    if options.screenOff { do { try PowerLease.sleepDisplays() } catch { note(error.localizedDescription) } }
    var lastPowerCheck=Date.distantPast
    while true {
        let signal=vb_take_signal()
        if signal != 0 {
            lease.release();record.protected=false;record.cleanup = .observe;record.outcome = .cancelled
            try store.save(record);child.signal(signal)
        }
        if record.outcome == .running {
            var reason:SessionOutcome?
            if store.isReleased(record.id) { reason = .detached }
            else if Date()>=record.deadline { reason = .expired }
            else if Date().timeIntervalSince(lastPowerCheck)>=5 {
                lastPowerCheck=Date()
                if !options.allowBattery && !BatteryReader.read().onAC { reason = .detached }
            }
            if let reason {
                record.outcome=reason;record.protected=false;record.cleanup = .observe;lease.release();try store.save(record)
                note("보호 해제 (\(reason.rawValue)). 명령은 계속 실행되며 자동 정리는 하지 않습니다.")
            }
        }
        // Revocation/expiry must win when completion occurs between polling ticks.
        if let code=try child.exitStatus() {
            if record.outcome == .running { record.outcome=code==0 ? .succeeded:.failed }
            lease.release();record.exitCode=code;record.protected=false;record.ended=Date();try store.save(record)
            note("작업 종료: \(code) · \(record.outcome.rawValue)");return code
        }
        Thread.sleep(forTimeInterval:0.5)
    }
}
