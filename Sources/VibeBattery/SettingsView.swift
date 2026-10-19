import SwiftUI
struct SettingsView:View {
    @EnvironmentObject var model:AppModel
    var body:some View {
        PageTitle(title:"내 방식대로",subtitle:"보호 방식과 기록을 직접 선택하세요.")
        Card {
            Text("충전과 에너지 모드").font(.headline)
            Text("배터리 / 어댑터별 저전력·자동·고전력 모드는 macOS가 지원하는 범위에서 선택합니다. 이 앱은 아직 시스템 전력 모드를 자동 변경하지 않습니다.").foregroundStyle(.secondary)
            Button("시스템 배터리 설정 열기") { model.openBatterySettings() }
        }
        Card {
            Text("기록과 개인정보").font(.headline)
            Toggle("배터리 이력 기록 · 최대 7일",isOn:$model.preferences.backgroundHistory).onChange(of:model.preferences.backgroundHistory) { _,_ in model.savePreferences() }
            Text("측정값은 이 맥에 저장합니다. AI 대화, 명령 인수, 터미널 출력, API 키는 기록하지 않습니다.").foregroundStyle(.secondary)
            Button("배터리 이력 삭제",role:.destructive) { model.clearHistory() }
        }
        Card {
            Text("검증된 기능과 개발 중인 기능").font(.headline)
            Text("현재 제공: 배터리·온도 조회, CPU 활동 목록, 선택 종료, 이력, 터미널 작업 보호와 제한된 리소스 정리.").foregroundStyle(.secondary)
            Text("개발 중: 앱 내부 충전 상한, 항해, 과열 충전 차단, 교정, 일정·단축어, MagSafe LED. 지원 여부가 확인되기 전에는 실행되지 않습니다.").foregroundStyle(.secondary)
            Link("GitHub에서 소스와 진행 상황 보기",destination:URL(string:"https://github.com/y-minion/vibebattery")!)
        }
    }
}
