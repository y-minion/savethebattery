import Foundation
import BatteryCore
import BatteryPlatform
@main struct VibeCLI {
    static func main() {
        let args=Array(CommandLine.arguments.dropFirst())
        do {
            switch args.first {
            case "status":
                let b=BatteryReader.read()
                if args.contains("--json") { print(String(data:try JSONEncoder().encode(b),encoding:.utf8)!) }
                else { print("배터리 \(b.percent.map(String.init) ?? "—")% · 건강도(추정) \(b.health.map(String.init) ?? "—")% · 온도 \(b.temperature.map { String(format:"%.1f°C",$0) } ?? "조회 불가") · \(b.onAC ? "어댑터":"배터리")") }
            case "run":exit(try runSession(RunOptions.parse(Array(args.dropFirst()))))
            case "resource":exit(try runResource(Array(args.dropFirst())))
            case "sessions":
                for r in AppPaths.sessions.all() { print("\(r.id.uuidString)  \(r.command)  \(r.outcome.rawValue)  보호:\(r.protected)") }
            case "release":
                guard args.count==2,let id=UUID(uuidString:args[1]) else { throw OptionError.invalid("release 뒤에 세션 UUID가 필요합니다.") }
                try AppPaths.sessions.release(id);print("보호 해제를 요청했습니다. 작업은 종료하지 않습니다.")
            default:print("""
            VibeBattery — 배터리와 터미널 작업 관리
              vbctl status [--json]
              vbctl run [--hours 4] [--screen-off] [--cleanup] [--allow-battery] -- command args
              vbctl resource [--keep] -- command args   (관리 세션 내부)
              vbctl sessions
              vbctl release UUID
            자동 정리는 resource로 직접 등록한 임시 작업에만 적용됩니다.
            --hours 만료 시 보호만 해제됩니다. 명령은 계속 실행되지만 macOS가 잠들 수 있습니다.
            """)
            }
        } catch { note(error.localizedDescription);exit(1) }
    }
}
