import SwiftUI
import BatteryCore
/// The Low Power Mode switch, shared by the menu window and the dashboard.
struct LowPowerView:View {
    @EnvironmentObject var model:AppModel
    @State private var error:String?
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            if let caption=LowPowerText.caption(model.helperStatus) {
                HStack {
                    Button("배터리 설정 열기") { model.openBatterySettings() }.buttonStyle(.bordered).controlSize(.small)
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                // The switch shows the real state; it moves only once macOS reports the change.
                Toggle("저전력 모드",isOn:Binding(get:{ model.lowPower },set:{ on in Task { error=await model.setLowPower(on) } }))
                if model.lowPowerConditional { Text(LowPowerText.conditional).font(.caption).foregroundStyle(.secondary) }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
}
