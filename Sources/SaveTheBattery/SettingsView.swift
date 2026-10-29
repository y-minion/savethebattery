import SwiftUI
import BatteryCore
import BatteryPlatform
struct SettingsView:View {
    @EnvironmentObject var model:AppModel
    var accessText:String {
        switch model.notificationAccess {
        case .allowed:return tr("Notifications allowed","알림 허용됨")
        case .denied:return tr("Notifications are denied","알림이 거부되어 있습니다")
        case .notAsked:return tr("Notification permission has not been asked yet","알림 권한을 아직 묻지 않았습니다")
        case .unavailable:return tr("Notifications are unavailable in a development run","개발 실행이라 알림을 쓸 수 없습니다")
        }
    }
    func flag(_ title:String,_ detail:String,_ key:WritableKeyPath<NotificationSettings,Bool>) -> some View {
        Toggle(isOn:Binding(get:{ model.preferences.notifications[keyPath:key] },set:{ model.preferences.notifications[keyPath:key]=$0;model.savePreferences() })) {
            VStack(alignment:.leading,spacing:2) { Text(title);Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
    var body:some View {
        PageTitle(title:tr("Settings","설정"),subtitle:tr("App-wide settings, notifications and history. Charging settings are on the Charge page.","앱 전체 설정과 알림, 기록을 정합니다. 충전 관련 설정은 충전 페이지에 있습니다."))
        Card {
            Text(tr("Notifications","알림")).font(.headline)
            HStack {
                Text(accessText).foregroundStyle(.secondary);Spacer()
                if model.notificationAccess == .notAsked { Button(tr("Allow notifications","알림 허용")) { model.requestNotifications() } }
                if model.notificationAccess == .denied { Button(tr("Open System Settings","시스템 설정 열기")) { model.openNotificationSettings() } }
                Button(tr("Send test notification","테스트 알림 보내기")) { model.sendTestNotification() }.disabled(model.notificationAccess != .allowed)
            }
            Text(tr("Charge status","충전 상태")).font(.subheadline.weight(.semibold))
            flag(tr("Charge limit reached","충전 상한 도달"),tr("When charging stops at the limit","충전 중 상한에 닿아 충전이 멈추면"),\.limitReached)
            flag(tr("Top-up finished","완충 끝남"),tr("When a one-time top-up reaches 99% or more","한 번 완충이 99% 이상이 되면"),\.topUpDone)
            flag(tr("Schedule failed","일정 실행 실패"),tr("When a schedule could not change the limit","일정이 상한을 바꾸지 못했을 때"),\.scheduleFailed)
            flag(tr("Schedule ran","일정 실행됨"),tr("Every time a schedule runs","일정이 실행될 때마다"),\.scheduleRan)
            flag(tr("Low battery","배터리 부족"),tr("When the battery drops to the level below while in use","배터리 사용 중 아래 기준 이하로 내려가면"),\.lowBattery)
            Stepper(tr("Low battery threshold \(model.preferences.notifications.lowAt)%","배터리 부족 기준 \(model.preferences.notifications.lowAt)%"),value:$model.preferences.notifications.lowAt,in:NotificationSettings.lowRange,step:5).onChange(of:model.preferences.notifications.lowAt) { _,_ in model.savePreferences() }
            flag(tr("Charge limit turned off or changed","충전 상한이 꺼지거나 바뀜"),tr("When the limit Save the Battery set is changed elsewhere","Save the Battery가 설정한 상한을 다른 곳에서 바꾸면"),\.limitChanged)
            flag(tr("Charge control unavailable","충전 제어 불가"),tr("When macOS no longer offers charge limiting","macOS가 충전 상한 기능을 더 이상 제공하지 않으면"),\.controlUnavailable)
            Text(tr("Protection alerts","보호 경고")).font(.subheadline.weight(.semibold))
            flag(tr("Battery too hot","배터리 고온"),tr("At or above the level below (+2°C while on battery)","아래 기준 이상(배터리 사용 중에는 +2°C)이면"),\.highTemperature)
            Stepper(tr("Hot threshold (while charging) \(Int(model.preferences.notifications.hotAt))°C","고온 기준(충전 중) \(Int(model.preferences.notifications.hotAt))°C"),value:$model.preferences.notifications.hotAt,in:NotificationSettings.hotRange,step:1).onChange(of:model.preferences.notifications.hotAt) { _,_ in model.savePreferences() }
            flag(tr("Other charge manager detected","다른 충전 관리 앱 감지"),tr("When another charge manager is detected and changes are blocked","다른 충전 관리 앱이 감지되어 변경을 막으면"),\.conflict)
            flag(tr("Heat hold problem","과열 보류 문제"),tr("Restore failed, stopped, apply failed, no temperature sensor","복원 실패, 멈춤, 적용 실패, 온도 센서 없음"),\.heatProblem)
            flag(tr("Heat hold started or ended","과열 보류 시작·해제"),tr("Every time a hold is set or released","보류를 걸거나 풀 때마다"),\.heatActivity)
            Text(tr("Vibe coding","바이브 코딩")).font(.subheadline.weight(.semibold))
            flag(tr("Task ended","작업 종료"),tr("Shows only the executable name and the time taken","실행 파일 이름과 걸린 시간만 표시"),\.sessionEnded)
            flag(tr("Task cancelled","작업 취소"),tr("A task cancelled with Ctrl-C or similar","Ctrl‑C 등으로 취소한 작업"),\.sessionCancelled)
            flag(tr("Sleep protection released","잠자기 방지 해제"),tr("When protection ends because the adapter was unplugged or time ran out","어댑터 분리나 시간 만료로 보호가 풀리면"),\.protectionReleased)
            Text(tr("Health analysis","건강 분석")).font(.subheadline.weight(.semibold))
            flag(tr("Battery drain during sleep","잠자기 중 배터리 소모"),tr("When the drain per hour was high on wake","깨어났을 때 시간당 소모가 크면"),\.sleepDrain)
            flag(tr("New suggestion","새 제안"),tr("The same suggestion at most once in 7 days","같은 제안은 7일에 한 번"),\.suggestions)
            flag(tr("Weekly summary","주간 요약"),tr("At the first reading after Monday 09:00","월요일 09:00 이후 첫 측정 때"),\.weeklySummary)
            Text(tr("Alerts appear only while the app is running and can be up to 2 minutes late. Focus modes may hide them, and lock screen previews follow your macOS notification settings.","앱이 실행 중일 때만 알리며 최대 2분 늦을 수 있습니다. 집중 모드에서는 가려질 수 있고, 잠금 화면 미리보기는 macOS 알림 설정을 따릅니다.")).font(.caption).foregroundStyle(.secondary)
        }.onAppear { model.checkNotifications() }
        Card {
            Text(tr("Menu bar","메뉴 막대")).font(.headline)
            Picker(tr("Display","표시 방식"),selection:Binding(get:{ model.preferences.menuBar.icon },set:{ model.preferences.menuBar.icon=$0;model.savePreferences() })) {
                ForEach(MenuIconStyle.allCases,id:\.self) { Text($0.title).tag($0) }
            }
            Text(tr("Menu window layout","메뉴 창 구성")).font(.subheadline.weight(.semibold))
            let sections=model.preferences.menuBar.sections
            ForEach(Array(sections.enumerated()),id:\.element.section) { i,s in
                HStack {
                    Toggle(s.section.title,isOn:Binding(get:{ s.visible },set:{ v in
                        if let k=model.preferences.menuBar.sections.firstIndex(where:{ $0.section==s.section }) { model.preferences.menuBar.sections[k].visible=v;model.savePreferences() }
                    }))
                    Spacer()
                    Button { model.preferences.menuBar.move(s.section,by:-1);model.savePreferences() } label: { Image(systemName:"chevron.up") }.disabled(i==0)
                    Button { model.preferences.menuBar.move(s.section,by:1);model.savePreferences() } label: { Image(systemName:"chevron.down") }.disabled(i==sections.count-1)
                }
            }
            Button(tr("Reset to defaults","기본값으로 되돌리기")) { model.preferences.menuBar = .default;model.savePreferences() }
        }
        Card {
            Text("MagSafe LED").font(.headline)
            let colors:[(String,WritableKeyPath<LEDSettings,LEDColor>)]=[(tr("Charging","충전 중"),\.charging),(tr("Paused at the limit or full","상한에서 멈춤 또는 완충"),\.paused),(tr("Charging on hold for heat","과열로 충전 보류"),\.heat)]
            Picker(tr("Display","표시 방식"),selection:Binding(get:{ model.preferences.led.mode },set:{ model.preferences.led.mode=$0;model.ledChanged() })) {
                ForEach(LEDMode.allCases,id:\.self) { Text($0.title).tag($0) }
            }
            if model.preferences.led.mode == .perState {
                ForEach(colors,id:\.0) { title,key in
                    Picker(title,selection:Binding(get:{ model.preferences.led[keyPath:key] },set:{ model.preferences.led[keyPath:key]=$0;model.ledChanged() })) {
                        ForEach(LEDColor.allCases,id:\.self) { Text($0.title).tag($0) }
                    }
                }
            }
            if model.ledUnsupported { Text(HelperReply.ledUnsupported.text).font(.caption).foregroundStyle(.secondary) }
            else if let caption=LowPowerText.caption(model.helperStatus) { Text(caption).font(.caption).foregroundStyle(.secondary) }
            else if !model.chargeConflicts.isEmpty { Text(tr("Another charge manager is present, so the LED is left alone.","다른 충전 관리 앱이 있어 LED를 바꾸지 않습니다.")).font(.caption).foregroundStyle(.secondary) }
            Text(tr("Works only when connected with a MagSafe cable. It has no effect when charging over USB-C.","MagSafe 케이블로 연결했을 때만 켜집니다. USB-C 단자로 충전하면 효과가 없습니다.")).font(.caption).foregroundStyle(.secondary)
        }.disabled(model.helperStatus != .ready || model.ledUnsupported)
        Card {
            Text(tr("Command line and Shortcuts","명령줄과 단축어")).font(.headline)
            Text(tr("While the app is running, you can change the charge limit from Terminal or Shortcuts.","앱이 실행 중이면 터미널이나 단축어에서 충전 상한을 바꿀 수 있습니다.")).foregroundStyle(.secondary)
            VStack(alignment:.leading,spacing:4) {
                ForEach(["stb charge set 70","stb charge topup","stb charge status --json"],id:\.self) { Text($0).font(.system(.callout,design:.monospaced)).textSelection(.enabled) }
            }
            Button(tr("Copy stb path","stb 경로 복사")) { model.copyText(ShellQuote.quote(model.cliPath)) }
            Text(tr("Search for 'Save the Battery' in the Shortcuts app to find its actions. You can also put stb commands in a Run Shell Script action.","단축어 앱에서 'Save the Battery'를 검색하면 전용 동작을 쓸 수 있습니다. 셸 스크립트 실행에 stb 명령을 넣어도 됩니다.")).font(.caption).foregroundStyle(.secondary)
        }
        Card {
            Text(tr("Startup and energy mode","시작과 에너지 모드")).font(.headline)
            Toggle(tr("Launch Save the Battery at login","로그인 시 Save the Battery 실행"),isOn:Binding(get:{ model.loginItem },set:{ model.setLoginItem($0) }))
            Text(tr("Choose Low Power, Automatic or High Power mode in macOS battery settings.","저전력·자동·고전력 모드는 macOS 배터리 설정에서 선택합니다.")).foregroundStyle(.secondary)
            Button(tr("Open system battery settings","시스템 배터리 설정 열기")) { model.openBatterySettings() }
        }
        Card {
            HStack { Text(tr("Updates","업데이트")).font(.headline);Spacer();Text(tr("Version \(ReleaseClient.bundleVersion)","버전 \(ReleaseClient.bundleVersion)")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            Toggle(tr("Check for new versions","새 버전 확인"),isOn:$model.preferences.checkUpdates).onChange(of:model.preferences.checkUpdates) { _,_ in model.savePreferences();model.scheduleUpdateChecks() }
            Text(tr("Once a day, Save the Battery asks GitHub for the latest release. Nothing about you or your Mac is sent.","하루에 한 번 GitHub에 최신 릴리스를 물어봅니다. 사용자나 Mac에 관한 정보는 보내지 않습니다.")).font(.callout).foregroundStyle(.secondary)
            if let u=model.availableUpdate {
                Text(tr("New version \(u.version)","새 버전 \(u.version)")).font(.subheadline.weight(.semibold))
                Link(tr("Open release page","릴리스 페이지 열기"),destination:u.url)
                Button(tr("Copy install command","설치 명령 복사")) { model.copyInstallCommand() }
            }
        }
        Card {
            Text(tr("History and privacy","기록과 개인정보")).font(.headline)
            Toggle(tr("Record battery history (charge 7 days · health analysis 1 year)","배터리 이력 기록 (잔량 7일 · 건강 분석 1년)"),isOn:$model.preferences.backgroundHistory).onChange(of:model.preferences.backgroundHistory) { _,_ in model.savePreferences() }
            Text(tr("Readings are stored on this Mac. AI conversations, command arguments, terminal output and API keys are never recorded.","측정값은 이 맥에 저장합니다. AI 대화, 명령 인수, 터미널 출력, API 키는 기록하지 않습니다.")).foregroundStyle(.secondary)
            Button(tr("Delete battery history","배터리 이력 삭제"),role:.destructive) { model.clearHistory() }
            Text(tr("Ended session records are kept for up to 30 days while the app runs. Running managed sessions are not deleted.","종료된 세션 기록은 앱 실행 중 최대 30일간 보관합니다. 실행 중인 관리 세션은 삭제하지 않습니다.")).font(.callout).foregroundStyle(.secondary)
            Button(tr("Delete ended session records","종료된 세션 기록 삭제"),role:.destructive) { model.clearInactiveSessions() }
        }
        Card {
            Text(tr("Verified and in-development features","검증된 기능과 개발 중인 기능")).font(.headline)
            Text(tr("Available now: battery and temperature readings, CPU activity list, quit on request, history, terminal task protection with limited resource cleanup, charge limit 50-100%, one-time top-up, charge schedules, command-line charge control, health analysis, notifications, a live menu bar icon and menu window, power flow, hardware charge level, a Low Power Mode switch, MagSafe LED.","현재 제공: 배터리·온도 조회, CPU 활동 목록, 선택 종료, 이력, 터미널 작업 보호와 제한된 리소스 정리, 충전 상한 50~100%, 한 번 완충, 충전 일정, 명령줄 충전 제어, 건강 분석, 알림, 실시간 메뉴 막대 아이콘과 메뉴 창, 전력 흐름, 하드웨어 잔량, 저전력 모드 스위치, MagSafe LED.")).foregroundStyle(.secondary)
            Text(tr("Checked on real hardware on this Mac: charge limit, one-time top-up, notifications. Heat hold in a real high-temperature situation is not yet verified. Not available: sailing lower limit, forced discharge, calibration (firmware limits).","이 Mac에서 실기기 확인: 충전 상한, 한 번 완충, 알림. 실제 고온 상황의 과열 보류는 아직 확인 전입니다. 미제공: 항해 하한 지정·강제 방전·교정(펌웨어 제약).")).foregroundStyle(.secondary)
            Link(tr("View source and progress on GitHub","GitHub에서 소스와 진행 상황 보기"),destination:URL(string:"https://github.com/y-minion/savethebattery")!)
        }
    }
}
