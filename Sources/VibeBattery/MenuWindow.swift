import SwiftUI
import AppKit
import BatteryCore
import BatteryPlatform
/// Proportional power flow; reused by the dashboard.
struct PowerBar:View {
    let summary:PowerSummary
    var compact=false
    private func color(_ s:PowerSegment) -> Color {
        switch s { case .adapterToMac:.green; case .adapterToBattery:.blue; case .batteryToMac:.orange }
    }
    private func watts(_ s:PowerSegment) -> Double {
        switch s { case .adapterToMac(let w),.adapterToBattery(let w),.batteryToMac(let w):w }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:compact ? 6:10) {
            Text(summary.headline).font(compact ? .callout.weight(.medium):.headline)
            let total=max(summary.segments.map(watts).reduce(0,+),0.001)
            // Tiny segments still show at 8% so they are not lost.
            let shares=summary.segments.map { max(watts($0)/total,0.08) }
            let sum=shares.reduce(0,+)
            GeometryReader { g in
                HStack(spacing:2) {
                    ForEach(Array(summary.segments.enumerated()),id:\.offset) { i,s in
                        RoundedRectangle(cornerRadius:3).fill(color(s)).frame(width:max(0,(g.size.width-CGFloat(summary.segments.count-1)*2)*shares[i]/sum))
                    }
                }
            }.frame(height:compact ? 8:12)
            HStack(spacing:10) {
                ForEach(Array(summary.segments.enumerated()),id:\.offset) { _,s in
                    HStack(spacing:4) { Circle().fill(color(s)).frame(width:6,height:6);Text(s.label).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if let a=summary.adapter { Text(a).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
struct MenuWindow:View {
    @EnvironmentObject var model:AppModel
    @Environment(\.openWindow) var openWindow
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            ForEach(model.preferences.menuBar.sections.filter(\.visible),id:\.section) { s in section(s.section) }
            Divider()
            VStack(alignment:.leading,spacing:6) {
                Button("대시보드 열기") { openWindow(id:"main");NSApp.activate(ignoringOtherApps:true) }
                Button("Claude 실행 명령 복사") { model.copyCommand("claude") }
                Button("Codex 실행 명령 복사") { model.copyCommand("codex") }
                Button("앱 종료") { NSApp.terminate(nil) }
            }.buttonStyle(.plain)
        }.padding(16).frame(width:300).onAppear { model.menuWindowOpen=true }.onDisappear { model.menuWindowOpen=false }
            .background(KeyWindowObserver { model.menuWindowOpen=$0 })
    }
    @ViewBuilder func section(_ s:MenuSection) -> some View {
        switch s {
        case .status:statusSection
        case .power:
            if let p=PowerSummary.make(model.battery) { PowerBar(summary:p,compact:true) }
        case .limit:limitSection
        case .topUp:topUpSection
        case .lowPower:EmptyView() // Task 6 adds its view here.
        case .battery:batterySection
        case .sessions:sessionsSection
        }
    }
    var statusSection:some View {
        VStack(alignment:.leading,spacing:2) {
            Text("\(model.battery.percent.map(String.init) ?? "—")%").font(.system(size:34,weight:.bold,design:.rounded))
            let parts=[ChargeText.limit(model.charge),model.battery.onAC ? "충전기 연결":"배터리 사용"]+(model.battery.temperature.map { [String(format:"%.1f°C",$0)] } ?? [])
            Text(parts.joined(separator:" · ")).font(.callout).foregroundStyle(.secondary)
        }
    }
    /// Why charge writes are unavailable, shared by the limit and topUp sections.
    var writeBlock:String? {
        if !model.chargeConflicts.isEmpty { return "\(model.chargeConflicts.map(\.name).joined(separator:", "))이(가) 충전을 관리하고 있어 바꿀 수 없습니다." }
        return model.charge.supported==true ? nil:"이 맥에서는 충전 상한을 바꿀 수 없습니다"
    }
    var limitSection:some View {
        let canWrite=writeBlock==nil
        let current=model.charge.enabled==true ? model.charge.limit:nil
        return VStack(alignment:.leading,spacing:6) {
            Text(MenuSection.limit.title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing:6) {
                ForEach(MenuQuick.limits,id:\.self) { l in
                    let on=current==l
                    Button("\(l)") { model.applyCharge(.setLimit(l)) }
                        .buttonStyle(.bordered).tint(on ? .mint:nil).fontWeight(on ? .bold:.regular)
                        .disabled(!canWrite || (l<ChargeCommand.userFloor && !model.helperStatus.canSetLimit))
                }
                Button("끄기") { model.applyCharge(.clearLimit) }.buttonStyle(.bordered).disabled(!canWrite)
            }.controlSize(.small)
            if let b=writeBlock { Text(b).font(.caption).foregroundStyle(model.chargeConflicts.isEmpty ? Color.secondary:Color.orange) }
            else if !model.helperStatus.canSetLimit { Text("80% 미만은 헬퍼가 필요합니다").font(.caption).foregroundStyle(.secondary) }
        }
    }
    var topUpSection:some View {
        let canWrite=writeBlock==nil
        return VStack(alignment:.leading,spacing:6) {
            if model.topUpActive { Button("완충 종료") { model.applyCharge(.endTopUp) }.disabled(!canWrite) }
            else { Button("한 번 100% 충전") { model.applyCharge(.startTopUp) }.disabled(!canWrite) }
            if let b=writeBlock { Text(b).font(.caption).foregroundStyle(model.chargeConflicts.isEmpty ? Color.secondary:Color.orange) }
            if let n=model.nextSchedule { Text("다음 일정 "+ScheduleText.when(n.at,now:Date(),calendar:.current)).font(.caption).foregroundStyle(.secondary) }
        }.controlSize(.small)
    }
    var batterySection:some View {
        let b=model.battery
        return VStack(alignment:.leading,spacing:4) {
            row("하드웨어 잔량",b.hardwarePercent.map { "\($0)%" })
            row("건강도(추정)",b.health.map { "\($0)%" })
            row("사이클",b.cycles.map(String.init))
        }
    }
    func row(_ title:String,_ value:String?) -> some View {
        HStack { Text(title).foregroundStyle(.secondary);Spacer();Text(value ?? "—") }.font(.callout)
    }
    var sessionsSection:some View {
        let active=model.activeSessions
        return VStack(alignment:.leading,spacing:2) {
            Text(active.isEmpty ? "실행 중인 작업 없음":"실행 중인 작업 \(active.count)개").font(.callout)
            if let s=active.max(by:{ $0.started<$1.started }) {
                let name=s.command.split(separator:" ").first.map { ($0 as NSString).lastPathComponent } ?? s.command
                Text(([name]+(s.protected ? ["잠자기 방지 중"]:[])+["\(max(0,Int(Date().timeIntervalSince(s.started)/60)))분"]).joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
/// Follows the hosting window's key state so the refresh timer stops when the popover closes even if the content view stays alive.
struct KeyWindowObserver:NSViewRepresentable {
    var onChange:(Bool)->Void
    final class Probe:NSView {
        var onChange:(Bool)->Void={ _ in }
        private var tokens:[NSObjectProtocol]=[]
        override func viewDidMoveToWindow() {
            stop()
            guard let w=window else { return }
            let c=NotificationCenter.default
            tokens=[(NSWindow.didBecomeKeyNotification,true),(NSWindow.didResignKeyNotification,false)].map { name,on in
                c.addObserver(forName:name,object:w,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.onChange(on) } }
            }
            if w.isKeyWindow { onChange(true) }
        }
        func stop() { tokens.forEach(NotificationCenter.default.removeObserver);tokens=[] }
    }
    func makeNSView(context:Context) -> Probe { let p=Probe();p.onChange=onChange;return p }
    func updateNSView(_ v:Probe,context:Context) { v.onChange=onChange }
    static func dismantleNSView(_ v:Probe,coordinator:()) { v.stop();v.onChange={ _ in } }
}
