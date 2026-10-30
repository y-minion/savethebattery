import SwiftUI
import BatteryCore
struct SessionsView:View {
    @EnvironmentObject var model:AppModel
    var body:some View {
        PageTitle(title:tr("Vibe coding","바이브 코딩"),subtitle:tr("Let the screen rest while registered terminal tasks keep running.","화면은 쉬게, 등록한 터미널 작업은 계속."))
        Card {
            Label(tr("Start in iTerm2 or Ghostty","iTerm2 · Ghostty에서 시작"),systemImage:"terminal.fill").font(.headline)
            Text(tr("Copy a command below and run it in Terminal. It uses your existing login and chat tools.","아래 명령을 복사해 터미널에서 실행하세요. 기존 로그인과 대화 도구를 그대로 사용합니다.")).foregroundStyle(.secondary)
            HStack { Button(tr("Copy Claude command","Claude 명령 복사")) { model.copyCommand("claude") };Button(tr("Copy Codex command","Codex 명령 복사")) { model.copyCommand("codex") } }.buttonStyle(PageButtonStyle(prominent:true))
            Text(model.command(for:"claude")).font(.system(.caption,design:.monospaced)).textSelection(.enabled).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:8))
            Text(tr("Screen lock, closing the lid and your own sleep settings still apply. An AI waiting for your input is not a finished task.","화면 잠금·덮개 닫기·사용자 잠자기 설정은 유지됩니다. 대화형 AI가 입력을 기다리는 상태는 작업 완료가 아닙니다.")).font(.caption).foregroundStyle(.secondary)
        }
        Card {
            Text(tr("Session settings","세션 설정")).font(.headline)
            Picker(tr("Protection time","작업 보호 시간"),selection:$model.preferences.hours) { ForEach([1.0,2,4,8,12,24],id:\.self) { Text(tr("\(Int($0)) h","\(Int($0))시간")).tag($0) } }.pickerStyle(.segmented)
            Toggle(tr("Turn the display off at start","시작할 때 디스플레이 끄기"),isOn:$model.preferences.screenOff)
            Toggle(tr("Clean up registered temporary resources after success","성공 종료 후 등록한 임시 리소스 자동 정리"),isOn:$model.preferences.cleanup)
            Text(tr("When the time runs out, only the sleep prevention ends. The task keeps running, but macOS may sleep. Protection also ends by default when the adapter is unplugged.","시간이 만료되면 잠자기 방지만 해제합니다. 작업은 계속 실행되지만 macOS가 잠들 수 있습니다. 어댑터 분리 시에도 기본적으로 보호를 해제합니다.")).font(.caption).foregroundStyle(.secondary)
        }.onChange(of:model.preferences.hours) { _,_ in model.savePreferences() }.onChange(of:model.preferences.screenOff) { _,_ in model.savePreferences() }.onChange(of:model.preferences.cleanup) { _,_ in model.savePreferences() }
        Card {
            HStack { Text(tr("Registered tasks","등록한 작업")).font(.headline);Spacer();Button(tr("Refresh","새로고침")) { model.refresh() } }
            if model.sessions.isEmpty { Text(tr("No registered tasks yet.","아직 등록한 작업이 없습니다.")).foregroundStyle(.secondary).padding(.vertical,20) }
            ForEach(model.sessions.prefix(20)) { r in
                HStack {
                    VStack(alignment:.leading,spacing:5) { Text(r.command).font(.body.bold());Text(model.status(r)).foregroundStyle(.secondary);Text(r.started.formatted()).font(.caption).foregroundStyle(.tertiary) }
                    Spacer()
                    if r.ended==nil && model.ownerAlive(r) { Button(tr("Release protection","보호 해제")) { model.release(r) } }
                }.padding(.vertical,8)
                Divider()
            }
        }
        Card {
            Text(tr("What cleanup covers","자동 정리의 범위")).font(.headline)
            Text(tr("Only temporary servers you registered inside a task with the stb resource -- command are cleaned up. Ordinary background processes and tasks of unclear origin are left alone. Use --keep for servers you want to keep.","작업 안에서 stb resource -- 명령으로 직접 등록한 임시 서버만 정리합니다. 일반 백그라운드 프로세스나 출처가 불분명한 작업은 건드리지 않습니다. 유지할 서버는 --keep을 사용하세요.")).foregroundStyle(.secondary)
        }
    }
}
