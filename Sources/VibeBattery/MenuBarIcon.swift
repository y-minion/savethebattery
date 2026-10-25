import SwiftUI
import AppKit
import BatteryCore
enum MenuBarIcon {
    static func glyphSymbol(_ s:MenuBarStatus) -> String? {
        switch s { case .charging:"bolt.fill"; case .paused:"powerplug.fill"; case .onBattery:nil; case .heatHold:"thermometer.medium" }
    }
    /// Character shown before the percent when only text is displayed.
    static func glyphText(_ s:MenuBarStatus) -> String {
        switch s { case .charging:"⚡︎"; case .paused:"⏸︎"; case .onBattery:""; case .heatHold:"🌡︎" }
    }
    /// A battery outline filled to `percent` with the status glyph knocked out of it. Template except for heat hold, which is orange.
    static func image(percent:Int?,status:MenuBarStatus) -> NSImage {
        let size=NSSize(width:26,height:14)
        let fraction=CGFloat(min(100,max(0,percent ?? 0)))/100
        let glyph=glyphSymbol(status).flatMap { NSImage(systemSymbolName:$0,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:9,weight:.bold)) }
        let image=NSImage(size:size,flipped:false) { _ in
            let color:NSColor = status == .heatHold ? .systemOrange : .black
            color.setStroke();color.setFill()
            let body=NSRect(x:0.75,y:0.75,width:22,height:12.5)
            let outline=NSBezierPath(roundedRect:body,xRadius:3.5,yRadius:3.5);outline.lineWidth=1.2;outline.stroke()
            NSBezierPath(roundedRect:NSRect(x:23.5,y:4.5,width:2,height:5),xRadius:1,yRadius:1).fill()
            if percent != nil {
                let inner=body.insetBy(dx:2,dy:2)
                NSBezierPath(roundedRect:NSRect(x:inner.minX,y:inner.minY,width:max(2,inner.width*fraction),height:inner.height),xRadius:1.5,yRadius:1.5).fill()
            }
            if let glyph {
                let r=NSRect(x:body.midX-glyph.size.width/2,y:body.midY-glyph.size.height/2,width:glyph.size.width,height:glyph.size.height)
                // Clear a halo first so the glyph stays readable over the fill, then draw it.
                glyph.draw(in:r.insetBy(dx:-1,dy:-1),from:.zero,operation:.destinationOut,fraction:1)
                glyph.draw(in:r,from:.zero,operation:.sourceOver,fraction:1)
            }
            return true
        }
        image.isTemplate = status != .heatHold
        return image
    }
}
