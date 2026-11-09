import SwiftUI
import BatteryCore
/// Charger, Mac and battery, with dots moving along the links that carry power; reused by the dashboard.
struct PowerFlowView:View {
    let summary:PowerSummary
    var percent:Int?
    var compact=false
    private var icon:CGFloat { compact ? 18:26 }
    private func w(_ v:Double) -> String { String(format:"%.0f W",v) }
    private var chargerActive:Bool { (summary.chargerW ?? 0)>=0.5 }
    var body:some View {
        VStack(alignment:.leading,spacing:compact ? 8:12) {
            Text(summary.headline).font(compact ? .callout.weight(.medium):.headline)
            HStack(alignment:.top,spacing:4) {
                node("powerplug.fill",tr("Charger","충전기"),summary.chargerW.map(w) ?? tr("Not connected","연결 안 됨"),tint:chargerActive ? .green:nil)
                FlowLine(direction:chargerActive ? .forward:.none,tint:.green).frame(height:icon)
                node("laptopcomputer",tr("Mac","맥"),w(summary.macW),tint:.primary)
                FlowLine(direction:batteryDirection,tint:batteryTint ?? .gray).frame(height:icon)
                node(batterySymbol,percent.map { tr("Battery \($0)%","배터리 \($0)%") } ?? tr("Battery","배터리"),batteryText,tint:batteryTint)
            }
            if let a=summary.adapter { Text(a).font(.caption).foregroundStyle(.secondary) }
            if let n=summary.note { Text(n).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
        }
    }
    private func node(_ symbol:String,_ title:String,_ value:String,tint:Color?) -> some View {
        VStack(spacing:2) {
            Image(systemName:symbol).font(.system(size:icon)).foregroundStyle(tint ?? .secondary).frame(height:icon)
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit().weight(.medium))
        }.fixedSize()
    }
    private var batteryDirection:FlowLine.Direction {
        switch summary.battery { case .charging:.forward; case .discharging:.backward; case .idle:.none }
    }
    private var batteryTint:Color? {
        switch summary.battery { case .charging:.blue; case .discharging:.orange; case .idle:nil }
    }
    private var batteryText:String {
        switch summary.battery {
        case .charging(let v):return "+"+w(v)
        case .discharging(let v):return "−"+w(v)
        case .idle:return tr("Holding","유지")
        }
    }
    private var batterySymbol:String {
        if case .charging=summary.battery { return "battery.100percent.bolt" }
        return BatterySymbol.name(percent:percent)
    }
}
/// A link between two nodes: dashed when idle, otherwise dots moving toward the receiving end.
private struct FlowLine:View {
    enum Direction { case none,forward,backward }
    let direction:Direction
    let tint:Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        if direction == .none || reduceMotion { Canvas { ctx,size in draw(ctx,size,time:0) } }
        // A low frame rate is enough for the dots, and keeps a battery app from spending power on its own animation.
        else { TimelineView(.animation(minimumInterval:1/15)) { t in Canvas { ctx,size in draw(ctx,size,time:t.date.timeIntervalSinceReferenceDate) } } }
    }
    private func draw(_ ctx:GraphicsContext,_ size:CGSize,time:Double) {
        let y=size.height/2,inset:CGFloat=4,length=size.width-inset*2
        guard length>12 else { return }
        var line=Path();line.move(to:CGPoint(x:inset,y:y));line.addLine(to:CGPoint(x:size.width-inset,y:y))
        guard direction != .none else {
            ctx.stroke(line,with:.color(.gray.opacity(0.45)),style:StrokeStyle(lineWidth:1.5,dash:[3,4]));return
        }
        ctx.stroke(line,with:.color(tint.opacity(0.3)),lineWidth:2)
        let forward=direction == .forward,gap:CGFloat=12
        var x=CGFloat((time*20).truncatingRemainder(dividingBy:Double(gap)))
        while x<length-6 {
            let px=forward ? inset+x:size.width-inset-x
            ctx.fill(Path(ellipseIn:CGRect(x:px-2,y:y-2,width:4,height:4)),with:.color(tint))
            x+=gap
        }
        let tip=forward ? size.width-inset:inset,back:CGFloat=forward ? -6:6
        var head=Path();head.move(to:CGPoint(x:tip,y:y));head.addLine(to:CGPoint(x:tip+back,y:y-4));head.addLine(to:CGPoint(x:tip+back,y:y+4));head.closeSubpath()
        ctx.fill(head,with:.color(tint))
    }
}
