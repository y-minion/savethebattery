import SwiftUI
import BatteryCore
import BatteryPlatform
struct DashboardView:View {
    @EnvironmentObject var model:AppModel
    var body:some View {
        PageTitle(title:"배터리의 오늘",subtitle:"실제 측정값으로 상태를 확인하고, 필요한 만큼만 충전하세요.")
        Card {
            HStack(spacing:24) {
                ZStack {
                    Circle().stroke(Color.mint.opacity(0.12),lineWidth:12)
                    Circle().trim(from:0,to:Double(model.battery.percent ?? 0)/100).stroke(Color.mint,style:StrokeStyle(lineWidth:12,lineCap:.round)).rotationEffect(.degrees(-90))
                    Text(model.battery.percent.map { "\($0)%" } ?? "—").font(.system(size:32,weight:.bold,design:.rounded))
                }.frame(width:120,height:120)
                VStack(alignment:.leading,spacing:12) {
                    Label(model.battery.onAC ? "어댑터 연결됨":"배터리 사용 중",systemImage:model.battery.onAC ? "powerplug.fill":"battery.75percent").font(.title3.bold())
                    Text(model.battery.charging ? "충전 중":"현재 충전하지 않음").foregroundStyle(.secondary)
                    if let hw=model.battery.hardwarePercent {
                        Text("하드웨어 잔량 \(hw)%").font(.callout).foregroundStyle(.secondary)
                            .help("macOS는 배터리 보호를 위해 표시 값을 조정합니다. 이 값은 배터리가 직접 보고한 남은 용량입니다.")
                    }
                    Text("측정 \(model.battery.timestamp.formatted(date:.omitted,time:.standard))").font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                VStack(spacing:8) {
                    Button("새로고침") { model.refresh() }.buttonStyle(.bordered)
                    Button("배터리 설정 열기") { model.openBatterySettings() }.buttonStyle(.bordered)
                }
            }
            Divider()
            LowPowerView(showsSettingsButton:false)
        }
        HStack(alignment:.top,spacing:16) {
            metric("용량 기반 건강도",value:model.battery.health.map { "\($0)%" } ?? "—",footnote:"설계 용량 대비 추정치",symbol:"heart.fill")
            metric("배터리 온도",value:model.battery.temperature.map { String(format:"%.1f°C",$0) } ?? "—",footnote:model.battery.temperatureSource ?? "센서 조회 불가",symbol:"thermometer.medium")
            metric("충전 사이클",value:model.battery.cycles.map(String.init) ?? "—",footnote:"시스템이 보고한 누적 횟수",symbol:"arrow.trianglehead.2.clockwise.rotate.90")
        }
        Card {
            HStack {
                Label("충전",systemImage:"bolt.batteryblock").font(.headline);Spacer()
                Button("충전 관리 열기") { model.section="charge" }.buttonStyle(.bordered)
            }
            Text(ChargeText.limit(model.charge)).font(.title2.weight(.semibold))
            if let why=model.lastChangeText { Text(why).foregroundStyle(.secondary) }
            Text(model.nextSchedule.map { "다음 일정: \(ScheduleText.when($0.at,now:Date(),calendar:.current)) · \($0.rule.name)" } ?? "예약된 일정 없음").font(.callout).foregroundStyle(.secondary)
        }
        Card {
            HStack {
                Label("건강 분석",systemImage:"heart.text.square").font(.headline)
                Text(model.healthReport.map { HealthText.trend($0.trend,calendar:.current) } ?? "측정 중").foregroundStyle(.secondary)
                Spacer()
                Button("자세히") { model.section="health" }.buttonStyle(.bordered)
            }
        }
        Card {
            Label("전력 흐름",systemImage:"bolt.horizontal").font(.headline)
            // PowerBar carries the headline, adapter text and legend.
            if let p=PowerSummary.make(model.battery) { PowerBar(summary:p) }
            else { Text("이 맥에서는 전력 흐름을 읽을 수 없습니다").foregroundStyle(.secondary) }
        }
        Card {
            HStack { Text("최근 잔량 이력").font(.headline);Spacer();Text("기기에만 저장").font(.caption).foregroundStyle(.secondary) }
            if model.history.count<2 { Text("측정값이 쌓이면 잔량 변화를 표시합니다.").foregroundStyle(.secondary).frame(height:85) }
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
