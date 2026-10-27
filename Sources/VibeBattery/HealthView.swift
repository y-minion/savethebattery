import SwiftUI
import BatteryCore
struct HealthView:View {
    @EnvironmentObject var model:AppModel
    @State private var monthly=false
    func hours(_ s:Double)->String { String(format:tr("%.1f h","%.1f시간"),s/3600) }
    func sleepText(_ e:SleepEvent)->String {
        let d=e.end.timeIntervalSince(e.start)
        let span=String(format:tr("%.1f h","%.1f시간"),d/3600)
        if let r=e.drainPerHour { return tr("\(span) · \(String(format:"%.2f",r))% per hour","\(span) · 시간당 \(String(format:"%.2f",r))%") }
        if e.onAC { return tr("\(span) · adapter connected","\(span) · 어댑터 연결") }
        if d<SleepEvent.minimumDuration { return tr("\(span) · under 1 hour, not calculated","\(span) · 1시간 미만이라 계산 안 함") }
        return tr("\(span) · no charge data, or charge rose","\(span) · 잔량 정보 없음 또는 증가")
    }
    func target(_ k:SuggestionKind)->(String,String) {
        switch k {
        case .chargeLimit:return ("dashboard",tr("To charge control","충전 제어로"))
        case .heatHold:return ("settings",tr("To settings","설정으로"))
        case .sleepDrain:return ("processes",tr("To apps and processes","앱과 프로세스로"))
        }
    }
    var body:some View {
        PageTitle(title:tr("Health analysis","건강 분석"),subtitle:tr("See your battery wear trend and charging habits from real measurements.","실제 측정값으로 수명 추세와 충전 습관을 확인하세요."))
        if let r=model.healthReport {
            Card {
                Label(tr("Current state","현재 상태"),systemImage:"heart.fill").font(.headline)
                if let h=r.health {
                    HStack(spacing:28) {
                        VStack(alignment:.leading) { Text(String(format:"%.1f%%",h)).font(.system(size:27,weight:.semibold,design:.rounded));Text(tr("Health (estimated)","건강도(추정)")).font(.caption).foregroundStyle(.secondary) }
                        VStack(alignment:.leading) { Text("\(r.cycles.map(String.init) ?? "—")\(r.designCycles.map { "/\($0)" } ?? "")").font(.system(size:27,weight:.semibold,design:.rounded));Text(tr("Cycles / design life","사이클 / 설계 수명")).font(.caption).foregroundStyle(.secondary) }
                        if let m=r.marginTo80 { VStack(alignment:.leading) { Text(m>0 ? String(format:"%.1f%%p",m):tr("80% or below","80% 이하")).font(.system(size:27,weight:.semibold,design:.rounded));Text(tr("Margin to 80%","80%까지 여유")).font(.caption).foregroundStyle(.secondary) } }
                    }
                    Text(tr("Current full-charge capacity against design capacity. It can differ from the maximum capacity macOS shows by 1 to 2 points.","설계 용량 대비 현재 완충 용량입니다. macOS가 표시하는 최대 용량과 1~2%p 다를 수 있습니다.")).font(.caption).foregroundStyle(.secondary)
                } else { Text(tr("No battery information","배터리 정보 없음")).foregroundStyle(.secondary) }
            }
            Card {
                Label(tr("Measured this week vs. last week","이번 주와 지난주 측정값 비교"),systemImage:"checkmark.seal").font(.headline)
                ForEach(Array(HealthText.factLines(r).enumerated()),id:\.offset) { _,l in Text(l).monospacedDigit() }
                DisclosureGroup(tr("Why a charge limit helps","충전 상한이 도움이 되는 이유")) {
                    VStack(alignment:.leading,spacing:6) {
                        ForEach(Array(ChargeLimitExplainer.paragraphs.enumerated()),id:\.offset) { _,p in Text(p).font(.callout).foregroundStyle(.secondary) }
                        ForEach(Array(ChargeLimitExplainer.sources.enumerated()),id:\.offset) { _,s in Link(s.title,destination:s.url).font(.caption) }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(.top,4)
                }
            }
            Card {
                Label(tr("Wear trend","수명 추세"),systemImage:"chart.line.downtrend.xyaxis").font(.headline)
                Text(HealthText.trend(r.trend,calendar:.current)).font(.title3.weight(.semibold))
                if let p=r.trend.cycles { Text(tr("Expected cycles to reach 80%: \(p.low) to \(p.high.map(String.init) ?? "unknown")","80% 도달 예상 사이클: \(p.low) ~ \(p.high.map(String.init) ?? "알 수 없음")")).foregroundStyle(.secondary) }
                Text(tr("Calculated only from the trend of measured health (Theil–Sen). A period is shown only after 30 days, at least 5 days measured and a change of at least 1 point; less data gives a wider range. Replacing the battery starts a new calculation.","실측 건강도의 추세(Theil–Sen)로만 계산합니다. 30일 이상, 5일 이상 측정, 1%p 이상 변화가 있어야 기간을 표시하며 데이터가 적을수록 범위가 넓습니다. 배터리를 교체하면 새로 계산합니다.")).font(.caption).foregroundStyle(.secondary)
            }
            Card {
                HStack {
                    Label(tr("Charging habits","충전 습관"),systemImage:"bolt.batteryblock").font(.headline);Spacer()
                    Picker("",selection:$monthly) { Text(tr("7 days","7일")).tag(false);Text(tr("30 days","30일")).tag(true) }.pickerStyle(.segmented).frame(width:140)
                }
                let u=monthly ? r.month:r.week
                Grid(alignment:.leading,horizontalSpacing:24,verticalSpacing:8) {
                    GridRow { Text(tr("Time measured","측정한 시간")).foregroundStyle(.secondary);Text(hours(u.observed)) }
                    GridRow { Text(tr("Charge 90%+ / 95%+","잔량 90% 이상 / 95% 이상")).foregroundStyle(.secondary);Text("\(hours(u.soc90)) / \(hours(u.soc95))") }
                    GridRow { Text(tr("35°C+ / 40°C+","35°C 이상 / 40°C 이상")).foregroundStyle(.secondary);Text("\(hours(u.hot35)) / \(hours(u.hot40))") }
                    GridRow { Text(tr("Adapter connected","어댑터 연결 비율")).foregroundStyle(.secondary);Text(u.observed>0 ? "\(Int((u.onAC/u.observed*100).rounded()))%":"—") }
                    GridRow { Text(tr("Average charge · peak temperature","평균 잔량 · 최고 온도")).foregroundStyle(.secondary);Text("\(u.averageSoC.map { "\(Int($0.rounded()))%" } ?? "—") · \(u.maxTemperature.map { String(format:"%.1f°C",$0) } ?? "—")") }
                    GridRow { Text(tr("Average stress","평균 스트레스")).foregroundStyle(.secondary);Text(u.averageStress.map { String(format:tr("%.2f (25°C · 40%% charge = 1)","%.2f (25°C·잔량 40%% = 1)"),$0) } ?? "—") }
                }
                Text(HealthText.stress(u)).font(.title3.weight(.semibold))
                Text(tr("\(HealthText.caveat) The limit comparison is an estimate recalculated from the same records with charge capped at 80%, and is not converted into a time span.","\(HealthText.caveat) 상한 비교는 같은 기록에서 잔량을 80%로 제한해 다시 계산한 근사치이며 기간으로 환산하지 않습니다.")).font(.caption).foregroundStyle(.secondary)
                Link(tr("Source: Battery University BU-808","근거: Battery University BU-808"),destination:URL(string:"https://batteryuniversity.com/article/bu-808-how-to-prolong-lithium-based-batteries")!).font(.caption)
            }
            Card {
                Label(tr("Drain during sleep","잠자기 중 소모"),systemImage:"moon.zzz").font(.headline)
                if r.sleeps.isEmpty { Text(tr("Shown once sleep records build up. Recorded only while the app is running.","잠자기 기록이 쌓이면 표시합니다. 앱이 실행 중일 때만 기록합니다.")).foregroundStyle(.secondary) }
                ForEach(Array(r.sleeps.prefix(10).enumerated()),id:\.offset) { _,e in
                    HStack {
                        Text(e.start.formatted(date:.abbreviated,time:.shortened)).monospacedDigit()
                        Spacer()
                        Text(sleepText(e)).foregroundStyle(e.isHigh ? Color.orange:Color.secondary)
                    }
                }
                Text(tr("Charge is reported in whole percent, so a drain is highlighted only when it exceeds 1% per hour after allowing for 1% rounding. Check for apps that prevent sleep or wake the Mac.","잔량이 정수로 보고되므로 1%의 반올림 오차를 빼고도 시간당 1%를 넘을 때만 강조합니다. 잠자기를 막거나 깨우는 앱이 있는지 확인해 보세요.")).font(.caption).foregroundStyle(.secondary)
            }
            Card {
                Label(tr("Suggestions","제안"),systemImage:"lightbulb").font(.headline)
                if r.suggestions.isEmpty { Text(tr("Nothing to change right now.","지금은 바꿀 것이 없습니다.")).foregroundStyle(.secondary) }
                ForEach(r.suggestions,id:\.kind) { s in
                    HStack(alignment:.top) {
                        Text(s.message);Spacer()
                        let t=target(s.kind)
                        Button(t.1) { model.section=t.0 }.buttonStyle(.bordered)
                    }
                }
                Toggle(tr("Notify me of new suggestions (the same one at most every 7 days)","새 제안이 생기면 알림 (같은 제안은 7일에 한 번)"),isOn:Binding(get:{ model.preferences.notifications.suggestions },set:{ model.preferences.notifications.suggestions=$0;model.savePreferences() }))
            }
            Card {
                Text(tr("Health analysis history","건강 분석 기록")).font(.headline)
                Text(model.preferences.backgroundHistory ? tr("Daily records (up to 1 year) and sleep records (last 30) are stored only on this Mac. Records are made only while the app is running, so turning on launch at login keeps the trend accurate.","하루 기록(최대 1년)과 잠자기 기록(최근 30회)을 이 맥에만 저장합니다. 앱이 실행 중일 때만 기록하므로 로그인 시 실행을 켜 두면 추세가 정확해집니다."):tr("Battery history is off in Settings, so no new records are collected.","설정에서 배터리 이력 기록이 꺼져 있어 새 기록을 수집하지 않습니다.")).foregroundStyle(.secondary)
                Button(tr("Delete health analysis history","건강 분석 기록 삭제"),role:.destructive) { model.clearHealth() }
            }
        } else { Card { Text(tr("Measuring.","측정 중입니다.")).foregroundStyle(.secondary) } }
    }
}
