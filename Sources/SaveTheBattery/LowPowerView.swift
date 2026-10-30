import SwiftUI
import BatteryCore
/// The Low Power Mode switch, shared by the menu window and the dashboard.
struct LowPowerView:View {
    @EnvironmentObject var model:AppModel
    /// The dashboard card already has its own button.
    var showsSettingsButton=true
    @State private var error:String?
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            if model.helperStatus != .ready && AppModel.runsFromApplications {
                Toggle(tr("Low Power Mode","저전력 모드"),isOn:Binding(get:{ model.lowPower },set:{ on in Task { await model.installHelper { error=await model.setLowPower(on) } } })).disabled(model.lowPowerBusy || model.helperBusy)
                Text(LowPowerText.installsOnFirstUse).font(.caption).foregroundStyle(.secondary)
            } else if let caption=LowPowerText.caption(model.helperStatus) {
                HStack {
                    if showsSettingsButton { Button(tr("Open Battery settings","배터리 설정 열기")) { model.openBatterySettings() }.buttonStyle(PageButtonStyle()).controlSize(.small) }
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                // The switch shows the real state; it moves only once macOS reports the change.
                Toggle(tr("Low Power Mode","저전력 모드"),isOn:Binding(get:{ model.lowPower },set:{ on in Task { error=await model.setLowPower(on) } })).disabled(model.lowPowerBusy)
                ForEach(model.lowPowerNotes,id:\.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.onChange(of:model.lowPower) { error=nil }
    }
}
