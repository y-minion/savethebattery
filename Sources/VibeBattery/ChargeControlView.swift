import SwiftUI
import BatteryCore
import BatteryPlatform
enum ChargeHelperText {
    @MainActor static func status(_ model:AppModel) -> String {
        switch model.helperStatus {
        case .notInstalled:return "헬퍼 설치 안 됨 · 80% 미만 상한에만 필요합니다. 터미널에서 실행: \(model.helperInstallCommand)"
        case .wrongLocation:return "헬퍼 설치됨 · 앱을 /Applications/VibeBattery.app에서 실행해야 헬퍼가 요청을 받습니다."
        case .unreachable:return "헬퍼가 응답하지 않습니다. 설치 스크립트를 다시 실행하세요: \(model.helperInstallCommand)"
        case .outdated:return "헬퍼 업데이트 필요 · 저전력 모드와 MagSafe LED를 쓰려면 다시 설치하세요: \(model.helperInstallCommand)"
        case .ready:return "헬퍼 사용 가능"
        }
    }
}
struct ChargeControlCard:View {
    @EnvironmentObject var model:AppModel
    @State private var target=80
    var canWrite:Bool { model.charge.supported==true && model.chargeConflicts.isEmpty }
    var needsHelper:Bool { target<ChargeCommand.userFloor && !model.helperStatus.canSetLimit }
    var helperText:String { ChargeHelperText.status(model) }
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
            Text(ChargeText.limit(model.charge)).font(model.charge.supported==false ? .callout:.system(size:27,weight:.semibold,design:.rounded))
            if let why=model.lastChangeText { Text(why).font(.callout).foregroundStyle(.secondary) }
            if !model.chargeConflicts.isEmpty {
                Label("\(model.chargeConflicts.map(\.name).joined(separator:", "))이(가) 충전을 관리하고 있어 VibeBattery는 값을 바꾸지 않습니다. 해당 앱을 종료하거나 삭제하면 제어할 수 있습니다.",systemImage:"exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            HStack(spacing:12) {
                Stepper("상한 \(target)%\(target==80 ? " (권장)":"")",value:$target,in:ChargeCommand.range,step:5).frame(maxWidth:180)
                Button("적용") { model.applyCharge(.setLimit(target)) }.buttonStyle(.borderedProminent).disabled(!canWrite || needsHelper)
                Button("상한 끄기") { model.applyCharge(.clearLimit) }.disabled(!canWrite)
            }
            if needsHelper { Text("80% 미만 상한을 쓸 수 없습니다. \(helperText)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack(spacing:12) {
                Button("한 번 100% 충전") { model.applyCharge(.startTopUp) }.disabled(!canWrite)
                if model.topUpActive { Button("완충 종료") { model.applyCharge(.endTopUp) }.disabled(!canWrite) }
            }
            if model.topUpActive { Text("완충 모드 유지 중 · macOS가 상한을 다시 켜면 자동으로 끝납니다.").font(.caption).foregroundStyle(.secondary) }
            else if model.topUpRequested != nil { Text("완충 요청됨 · macOS 반영을 기다리는 중").font(.caption).foregroundStyle(.secondary) }
            Text("과열 보류: \(model.heatStatus)").font(.callout)
            Text("상한은 앱을 종료해도 macOS가 유지합니다.").font(.caption).foregroundStyle(.secondary)
            Text("항해 하한 지정·강제 방전·교정은 이 macOS 펌웨어에서 어댑터 차단 없이 불가능해 제공하지 않습니다. 재충전 시점은 macOS가 정합니다.").font(.caption).foregroundStyle(.secondary)
        }.onAppear { target=model.charge.limit.map { min(100,max(50,($0+ChargeCommand.step-1)/ChargeCommand.step*ChargeCommand.step)) } ?? 80 }
    }
}
