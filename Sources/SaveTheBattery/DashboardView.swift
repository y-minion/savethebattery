import SwiftUI
import BatteryCore
import BatteryPlatform
struct DashboardView:View {
    static var hardwareCaption:String { tr("macOS adjusts the displayed value to protect the battery. This is the remaining capacity the battery itself reports.","macOS는 배터리 보호를 위해 표시 값을 조정합니다. 이 값은 배터리가 직접 보고한 남은 용량입니다.") }
    @EnvironmentObject var model:AppModel
    var body:some View {
        PageTitle(title:tr("Battery today","배터리의 오늘"),subtitle:tr("Check the state from real readings and charge only as much as you need.","실제 측정값으로 상태를 확인하고, 필요한 만큼만 충전하세요."))
        if model.showsMoveCard { MoveToApplicationsCard() }
        if model.suggestsLimit { LimitTipCard() }
        Card {
            HStack(spacing:24) {
                ZStack {
                    Circle().stroke(Color.mint.opacity(0.12),lineWidth:12)
                    Circle().trim(from:0,to:Double(model.battery.percent ?? 0)/100).stroke(Color.mint,style:StrokeStyle(lineWidth:12,lineCap:.round)).rotationEffect(.degrees(-90))
                    Text(model.battery.percent.map { "\($0)%" } ?? "—").font(.system(size:32,weight:.bold,design:.rounded))
                }.frame(width:120,height:120)
                VStack(alignment:.leading,spacing:12) {
                    Label(model.battery.onAC ? tr("Adapter connected","어댑터 연결됨"):tr("Running on battery","배터리 사용 중"),systemImage:model.battery.onAC ? "powerplug.fill":"battery.75percent").font(.title3.bold())
                    Text(model.battery.charging ? tr("Charging","충전 중"):tr("Not charging right now","현재 충전하지 않음")).foregroundStyle(.secondary)
                    if let hw=model.battery.hardwarePercent {
                        Text(tr("Hardware charge \(hw)%","하드웨어 잔량 \(hw)%")).font(.callout).foregroundStyle(.secondary)
                            .help(Self.hardwareCaption)
                        Text(Self.hardwareCaption).font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal:false,vertical:true)
                    }
                    Text(tr("Measured \(model.battery.timestamp.formatted(date:.omitted,time:.standard))","측정 \(model.battery.timestamp.formatted(date:.omitted,time:.standard))")).font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                VStack(spacing:8) {
                    Button(tr("Refresh","새로고침")) { model.refresh() }.buttonStyle(.bordered)
                    Button(tr("Open battery settings","배터리 설정 열기")) { model.openBatterySettings() }.buttonStyle(.bordered)
                }
            }
            Divider()
            LowPowerView(showsSettingsButton:false)
        }
        HStack(alignment:.top,spacing:16) {
            metric(tr("Capacity-based health","용량 기반 건강도"),value:model.battery.health.map { "\($0)%" } ?? "—",footnote:tr("Estimate against design capacity","설계 용량 대비 추정치"),symbol:"heart.fill")
            metric(tr("Battery temperature","배터리 온도"),value:model.battery.temperature.map { String(format:"%.1f°C",$0) } ?? "—",footnote:model.battery.temperatureSource ?? tr("Sensor unavailable","센서 조회 불가"),symbol:"thermometer.medium")
            metric(tr("Charge cycles","충전 사이클"),value:model.battery.cycles.map(String.init) ?? "—",footnote:tr("Total count reported by the system","시스템이 보고한 누적 횟수"),symbol:"arrow.trianglehead.2.clockwise.rotate.90")
        }
        Card {
            HStack {
                Label(tr("Charge","충전"),systemImage:"bolt.batteryblock").font(.headline);Spacer()
                Button(tr("Open charge management","충전 관리 열기")) { model.section="charge" }.buttonStyle(.bordered)
            }
            Text(ChargeText.limit(model.charge)).font(.title2.weight(.semibold))
            if let why=model.lastChangeText { Text(why).foregroundStyle(.secondary) }
            Text(model.nextSchedule.map { tr("Next schedule: \(ScheduleText.when($0.at,now:Date(),calendar:.current)) · \($0.rule.name)","다음 일정: \(ScheduleText.when($0.at,now:Date(),calendar:.current)) · \($0.rule.name)") } ?? tr("No schedule set","예약된 일정 없음")).font(.callout).foregroundStyle(.secondary)
        }
        Card {
            HStack {
                Label(tr("Health analysis","건강 분석"),systemImage:"heart.text.square").font(.headline)
                Spacer()
                Button(tr("Details","자세히")) { model.section="health" }.buttonStyle(.bordered)
            }
            if let r=model.healthReport {
                Text(tr("This week vs. last week","이번 주와 지난주 비교")).font(.caption).foregroundStyle(.secondary)
                ForEach(Array(HealthText.factLines(r).enumerated()),id:\.offset) { _,l in Text(l).monospacedDigit() }
            }
            Text(model.healthReport.map { HealthText.trend($0.trend,calendar:.current) } ?? tr("Measuring","측정 중")).foregroundStyle(.secondary)
            if let r=model.healthReport {
                Text(HealthText.stress(r.week)).font(.callout).foregroundStyle(.secondary)
                Text(HealthText.caveat).font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup(tr("Why a charge limit helps","충전 상한이 도움이 되는 이유")) {
                VStack(alignment:.leading,spacing:6) {
                    ForEach(Array(ChargeLimitExplainer.paragraphs.enumerated()),id:\.offset) { _,p in Text(p).font(.callout).foregroundStyle(.secondary) }
                    ForEach(Array(ChargeLimitExplainer.sources.enumerated()),id:\.offset) { _,s in Link(s.title,destination:s.url).font(.caption) }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(.top,4)
            }
        }
        Card {
            Label(tr("Power flow","전력 흐름"),systemImage:"bolt.horizontal").font(.headline)
            // PowerBar carries the headline, adapter text and legend.
            if let p=PowerSummary.make(model.battery) { PowerBar(summary:p) }
            else { Text(tr("Power flow cannot be read on this Mac","이 맥에서는 전력 흐름을 읽을 수 없습니다")).foregroundStyle(.secondary) }
        }
        Card {
            HStack { Text(tr("Recent charge history","최근 잔량 이력")).font(.headline);Spacer();Text(tr("Stored on this device only","기기에만 저장")).font(.caption).foregroundStyle(.secondary) }
            if model.history.count<2 { Text(tr("Charge changes show once readings accumulate.","측정값이 쌓이면 잔량 변화를 표시합니다.")).foregroundStyle(.secondary).frame(height:85) }
            else { BatteryGraph(values:model.history.suffix(120).compactMap { $0.percent.map(Double.init) }).frame(height:90) }
        }
    }
    func metric(_ title:String,value:String,footnote:String,symbol:String)->some View {
        Card { Label(title,systemImage:symbol).font(.caption).foregroundStyle(.secondary);Text(value).font(.system(size:27,weight:.semibold,design:.rounded));Text(footnote).font(.caption2).foregroundStyle(.tertiary) }
    }
}
struct BatteryGraph:View {
    var values:[Double]
    var body:some View {
        GeometryReader { size in
            Path { path in
                for (i,value) in values.enumerated() {
                    let point=CGPoint(x:CGFloat(i)/CGFloat(max(1,values.count-1))*size.size.width,y:(1-value/100)*size.size.height)
                    if i==0 { path.move(to:point) } else { path.addLine(to:point) }
                }
            }.stroke(Color.mint,style:StrokeStyle(lineWidth:2.5,lineCap:.round,lineJoin:.round))
        }
    }
}
