import SwiftUI
import BatteryCore
import BatteryPlatform
struct ChargeControlCard:View {
    @EnvironmentObject var model:AppModel
    @State private var target=80
    var canWrite:Bool { model.charge.supported==true && model.chargeConflicts.isEmpty }
    var needsHelper:Bool { target<ChargeCommand.userFloor && !model.helperInstalled }
    var originText:String {
        switch model.chargeOrigin {
        case .vibeBattery:return "VibeBattery가 설정"
        case .external:return "다른 앱 또는 시스템 설정에서 설정"
        case .none:return "상한 없음"
        case .unknown:return "확인 불가"
        }
    }
    var body:some View {
        Card {
            HStack { Label("충전 제어",systemImage:"shield.lefthalf.filled").font(.headline);Spacer();Text(originText).font(.caption).foregroundStyle(.secondary) }
            Text(ChargeText.limit(model.charge)).font(.system(size:27,weight:.semibold,design:.rounded))
            if !model.chargeConflicts.isEmpty {
                Label("\(model.chargeConflicts.map(\.name).joined(separator:", "))이(가) 충전을 관리하고 있어 VibeBattery는 값을 바꾸지 않습니다. 해당 앱을 종료하거나 삭제하면 제어할 수 있습니다.",systemImage:"exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            HStack(spacing:12) {
                Stepper("상한 \(target)%",value:$target,in:ChargeCommand.range,step:5).frame(maxWidth:180)
                Button("적용") { model.applyCharge(.setLimit(target)) }.buttonStyle(.borderedProminent).disabled(!canWrite || needsHelper)
                Button("상한 끄기") { model.applyCharge(.clearLimit) }.disabled(!canWrite)
            }
            if needsHelper { Text("80% 미만은 헬퍼 설치 후 사용할 수 있습니다. 터미널에서 실행: \(model.helperInstallCommand)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack(spacing:12) {
                Button("한 번 100% 충전") { model.applyCharge(.startTopUp) }.disabled(!canWrite)
                if model.topUpRequested != nil { Button("완충 종료") { model.applyCharge(.endTopUp) }.disabled(!canWrite) }
            }
            Text("과열 보류: \(model.heatStatus)").font(.callout)
            Text("헬퍼 \(model.helperInstalled ? "설치됨":"설치 안 됨") · 상한은 앱을 종료해도 macOS가 유지합니다.").font(.caption).foregroundStyle(.secondary)
            Text("항해 하한 지정·강제 방전·교정은 이 macOS 펌웨어에서 어댑터 차단 없이 불가능해 제공하지 않습니다. 재충전 시점은 macOS가 정합니다.").font(.caption).foregroundStyle(.secondary)
        }.onAppear { target=model.charge.limit.map { min(100,max(50,$0)) } ?? 80 }
    }
}
