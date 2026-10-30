import SwiftUI
import AppKit
import BatteryCore
import BatteryPlatform
@main struct SaveTheBatteryApp: App {
    @StateObject private var model=AppModel.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body:some Scene {
        // A single window: opening it again brings the open one forward instead of adding another.
        Window("Save the Battery",id:"main") { RootView().environmentObject(model).frame(minWidth:900,minHeight:650).tint(.mint) }
            .defaultSize(width:1050,height:740)
        MenuBarExtra {
            MenuWindow().environmentObject(model)
        } label: { MenuLabel().environmentObject(model) }.menuBarExtraStyle(.window)
    }
}
/// Always rendered, so it is where the app keeps a way to reopen the window for notification clicks.
struct MenuLabel:View {
    @EnvironmentObject var model:AppModel
    @Environment(\.openWindow) var openWindow
    var body:some View {
        let style=model.preferences.menuBar.icon,text="\(model.battery.percent.map(String.init) ?? "—")%"
        // Plain sibling views so the menu bar keeps adapting the template icon.
        Group {
            if style != .percentOnly { Image(nsImage:MenuBarIcon.image(percent:model.battery.percent,status:model.menuStatus)) }
            if style == .percentOnly { Text(MenuBarIcon.glyphText(model.menuStatus)+text) }
            else if style == .iconAndPercent { Text(text) }
        }.onAppear { model.openMain={ openWindow(id:"main") } }
    }
}
struct RootView:View {
    @EnvironmentObject var model:AppModel
    private var items:[(String,String,String)] {[("dashboard",tr("Dashboard","대시보드"),"square.grid.2x2"),("charge",tr("Charge","충전"),"bolt.batteryblock"),("health",tr("Health analysis","건강 분석"),"heart.text.square"),("processes",tr("Apps and processes","앱과 프로세스"),"waveform.path.ecg"),("sessions",tr("Vibe coding","바이브 코딩"),"terminal"),("settings",tr("Settings","설정"),"slider.horizontal.3")]}
    var body:some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:26) {
                HStack { Image(systemName:"leaf.fill").foregroundStyle(.mint); Text("Save the Battery").font(.title3.bold()) }.padding(.top,24)
                VStack(spacing:8) {
                    ForEach(items,id:\.0) { item in
                        Button { model.section=item.0 } label: {
                            Label(item.1,systemImage:item.2).font(.system(size:14,weight:.medium)).padding(12)
                        }.buttonStyle(HoverRowStyle(selected:model.section==item.0)).foregroundStyle(model.section==item.0 ? Color.mint:Color.primary)
                    }
                }
                Spacer()
                Label(tr("Stored locally · Free · Open source","로컬 저장 · 무료 · 오픈소스"),systemImage:"lock.shield").font(.caption).foregroundStyle(.secondary)
                Text(tr("Version \(ReleaseClient.bundleVersion)","버전 \(ReleaseClient.bundleVersion)")).font(.caption2).foregroundStyle(.tertiary).padding(.bottom,20)
            }.padding(.horizontal,16).frame(width:210).background(.ultraThinMaterial)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    switch model.section {
                    case "charge":ChargeView()
                    case "health":HealthView()
                    case "processes":ProcessesView()
                    case "sessions":SessionsView()
                    case "settings":SettingsView()
                    default:DashboardView()
                    }
                }.padding(30).frame(maxWidth:.infinity,alignment:.leading).buttonStyle(PageButtonStyle()).disclosureGroupStyle(HoverDisclosureStyle())
            }.background(Color(nsColor:.windowBackgroundColor))
        }.alert("Save the Battery",isPresented:Binding(get:{model.message != nil},set:{if !$0 {model.message=nil}})) { Button(tr("OK","확인")) { model.message=nil } } message: { Text(model.message ?? "") }
    }
}
struct Card<Content:View>:View {
    @ViewBuilder var content:Content
    var body:some View { VStack(alignment:.leading,spacing:14) { content }.frame(maxWidth:.infinity,alignment:.leading).padding(22).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).strokeBorder(Color.primary.opacity(0.06))) }
}
/// A borderless row that highlights on hover and press; the whole highlighted area takes the click.
struct HoverRowStyle:ButtonStyle {
    var selected=false
    /// Resting fill, for rows that are tinted before any hover.
    var idle=Color.clear
    var cornerRadius:CGFloat=10
    func makeBody(configuration:Configuration) -> some View { Row(configuration:configuration,style:self) }
    private struct Row:View {
        let configuration:Configuration;let style:HoverRowStyle
        @State private var hovering=false
        @Environment(\.isEnabled) private var enabled
        var body:some View {
            let shape=RoundedRectangle(cornerRadius:style.cornerRadius)
            configuration.label
                .frame(maxWidth:.infinity,alignment:.leading)
                .contentShape(shape)
                .background(highlight,in:shape)
                .background(style.idle,in:shape)
                .onHover { hovering=$0 }
        }
        private var highlight:Color {
            if style.selected { return Color.mint.opacity(configuration.isPressed ? 0.22:0.14) }
            if !enabled { return .clear }
            return configuration.isPressed ? Color.primary.opacity(0.12):hovering ? Color.primary.opacity(0.06):.clear
        }
    }
}
/// Collapsible sections: the whole header row highlights on hover and toggles on click, not just the chevron.
struct HoverDisclosureStyle:DisclosureGroupStyle {
    func makeBody(configuration:Configuration) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Button { withAnimation(.easeOut(duration:0.15)) { configuration.isExpanded.toggle() } } label: {
                HStack(spacing:8) {
                    Image(systemName:"chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90:0))
                    configuration.label
                }.padding(.vertical,6).padding(.horizontal,8)
            }.buttonStyle(HoverRowStyle(cornerRadius:8)).padding(.horizontal,-8)
            if configuration.isExpanded { configuration.content }
        }
    }
}
/// Page buttons: a roomy tinted shape that lightens on hover and darkens while pressed; the whole shape takes the click.
struct PageButtonStyle:ButtonStyle {
    var prominent=false
    func makeBody(configuration:Configuration) -> some View { Content(configuration:configuration,prominent:prominent) }
    private struct Content:View {
        let configuration:Configuration;let prominent:Bool
        @State private var hovering=false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.controlSize) private var size
        var body:some View {
            let small=size == .small || size == .mini
            let shape=RoundedRectangle(cornerRadius:small ? 6:8)
            let pressed=configuration.isPressed && enabled
            configuration.label
                .font(small ? .callout.weight(.medium):.body.weight(.medium))
                .foregroundStyle(prominent ? Color.white:configuration.role == .destructive ? Color.red:Color.primary)
                .padding(.horizontal,small ? 10:14).padding(.vertical,small ? 4:7)
                .background(prominent ? Color.mint:Color.primary.opacity(0.07),in:shape)
                .overlay(shape.fill(pressed ? Color.black.opacity(0.14):hovering ? Color.white.opacity(prominent ? 0.16:0.07):.clear).allowsHitTesting(false))
                .contentShape(shape)
                .opacity(enabled ? 1:0.45)
                .onHover { hovering=$0 }
                .animation(.easeOut(duration:0.12),value:hovering)
        }
    }
}
struct PageTitle:View {
    var title:String;var subtitle:String
    var body:some View { VStack(alignment:.leading,spacing:8) { Text(title).font(.system(size:30,weight:.bold));Text(subtitle).font(.callout).foregroundStyle(.secondary) } }
}
