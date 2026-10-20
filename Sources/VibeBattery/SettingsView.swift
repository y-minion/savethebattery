import SwiftUI
struct SettingsView:View {
    @EnvironmentObject var model:AppModel
    var body:some View {
        PageTitle(title:"내 방식대로",subtitle:"보호 방식과 기록을 직접 선택하세요.")
        Card {
            Text("과열 시 충전 보류").font(.headline)
            Toggle("배터리 온도가 높으면 충전 보류",isOn:Binding(get:{ model.preferences.heat.enabled },set:{ model.setHeatEnabled($0) }))
            Stepper("보류 온도 \(Int(model.preferences.heat.holdAt))°C",value:$model.preferences.heat.holdAt,in:30...45,step:1).onChange(of:model.preferences.heat.holdAt) { _,_ in model.savePreferences() }
            Stepper("재개 온도 \(Int(model.preferences.heat.resumeAt))°C",value:$model.preferences.heat.resumeAt,in:25...44,step:1).onChange(of:model.preferences.heat.resumeAt) { _,_ in model.savePreferences() }
            Text("기본값 35°C/32°C는 Apple 공식 기준이 아닌 보수적 설계값입니다. 잔량 50% 이상에서 충전 중일 때만 상한을 현재 잔량으로 낮추며, 앱이 실행 중일 때만 동작합니다. Apple의 하드웨어 보호를 대체하지 않습니다.").font(.caption).foregroundStyle(.secondary)
        }
        Card {
            Text("시작과 에너지 모드").font(.headline)
            Toggle("로그인 시 VibeBattery 실행",isOn:Binding(get:{ model.loginItem },set:{ model.setLoginItem($0) }))
            Text("저전력·자동·고전력 모드는 macOS 배터리 설정에서 선택합니다.").foregroundStyle(.secondary)
            Button("시스템 배터리 설정 열기") { model.openBatterySettings() }
        }
        Card {
            Text("기록과 개인정보").font(.headline)
            Toggle("배터리 이력 기록 (잔량 7일 · 건강 분석 1년)",isOn:$model.preferences.backgroundHistory).onChange(of:model.preferences.backgroundHistory) { _,_ in model.savePreferences() }
            Text("측정값은 이 맥에 저장합니다. AI 대화, 명령 인수, 터미널 출력, API 키는 기록하지 않습니다.").foregroundStyle(.secondary)
            Button("배터리 이력 삭제",role:.destructive) { model.clearHistory() }
            Text("종료된 세션 기록은 앱 실행 중 최대 30일간 보관합니다. 실행 중인 관리 세션은 삭제하지 않습니다.").font(.callout).foregroundStyle(.secondary)
            Button("종료된 세션 기록 삭제",role:.destructive) { model.clearInactiveSessions() }
        }
        Card {
            Text("검증된 기능과 개발 중인 기능").font(.headline)
            Text("현재 제공: 배터리·온도 조회, CPU 활동 목록, 선택 종료, 이력, 터미널 작업 보호와 제한된 리소스 정리.").foregroundStyle(.secondary)
            Text("구현됨(이 Mac에서 실제 쓰기 검증 대기): 충전 상한 50~100%, 한 번 완충, 과열 시 충전 보류. 미제공: 항해 하한 지정·강제 방전·교정(펌웨어 제약). 건강 분석: 하루 기록과 잠자기 소모를 이 맥에 최대 1년 보관하며 수명 추세는 30일 이상 기록 후 표시. 개발 예정: 알림, 일정·단축어, MagSafe LED.").foregroundStyle(.secondary)
            Link("GitHub에서 소스와 진행 상황 보기",destination:URL(string:"https://github.com/y-minion/vibebattery")!)
        }
    }
}
