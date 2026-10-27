import Foundation
import MacBridge
import BatteryCore
import BatteryPlatform
func runResource(_ args:[String]) throws -> Int32 {
    var arguments=args;let keep=arguments.first=="--keep"
    if keep { arguments.removeFirst() }
    guard arguments.first=="--",arguments.count>1,let raw=ProcessInfo.processInfo.environment["VIBEBATTERY_SESSION"],let id=UUID(uuidString:raw),
          let initial=AppPaths.sessions.load(id),initial.outcome == .running,let owner=initial.owner,
          ProcessReader.one(owner.pid)?.identity==owner else { throw PlatformError.message(tr("Use resource as '-- command' inside a running managed session.","resource는 실행 중인 관리 세션 안에서 -- 명령 형식으로 사용하세요.")) }
    vb_watch_signals()
    let child=try ChildCommand(Array(arguments.dropFirst()),environment:ProcessInfo.processInfo.environment)
    var sent=false;var cancelled=false
    while true {
        let signal=vb_take_signal();if signal != 0 { cancelled=true;child.signal(signal) }
        if let status=try child.exitStatus() { return status }
        if !sent && !cancelled && !keep && !AppPaths.sessions.isReleased(id),let record=AppPaths.sessions.load(id),record.owner==owner,
           SessionPolicy.cleanupAllowed(outcome:record.outcome,registered:true,shared:false,policy:record.cleanup) {
            child.signal(SIGTERM);sent=true
            note(tr("Asked the temporary resource registered by the finished task to quit. It is not force-killed if it does not answer.","완료된 작업의 명시적으로 등록한 임시 리소스에 정상 종료를 요청했습니다. 응답이 없으면 강제 종료하지 않습니다."))
        }
        Thread.sleep(forTimeInterval:1)
    }
}
