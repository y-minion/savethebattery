import SwiftUI
import BatteryCore
import BatteryPlatform
enum ChargeHelperText {
    @MainActor static func status(_ model:AppModel) -> String {
        switch model.helperStatus {
        case .notInstalled:return tr("Helper not installed · needed only for limits below 80%. Install it below.","헬퍼 설치 안 됨 · 80% 미만 상한에만 필요합니다. 아래에서 설치하세요.")
        case .wrongLocation:return tr("Helper installed · run the app from /Applications/VibeBattery.app so the helper accepts requests.","헬퍼 설치됨 · 앱을 /Applications/VibeBattery.app에서 실행해야 헬퍼가 요청을 받습니다.")
        case .unreachable:return tr("The helper is not responding. Reinstall it below.","헬퍼가 응답하지 않습니다. 아래에서 다시 설치하세요.")
        case .outdated:return tr("Helper update needed · reinstall it below to use Low Power Mode and MagSafe LED.","헬퍼 업데이트 필요 · 저전력 모드와 MagSafe LED를 쓰려면 아래에서 다시 설치하세요.")
        case .ready:return tr("Helper ready","헬퍼 사용 가능")
        }
    }
}
/// Install, reinstall and remove the root helper with the system password dialog; the Terminal command stays as a fallback.
struct HelperInstallControls:View {
    @EnvironmentObject var model:AppModel
    private static let selfBuilt=CodeSigningIdentity.own == .adHoc
    private static let inApplications=(Bundle.main.bundlePath as NSString).standardizingPath == "/Applications/VibeBattery.app"
    private var installed:Bool { model.helperStatus != .notInstalled }
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            HStack(spacing:12) {
                Button(installed ? tr("Reinstall helper…","헬퍼 다시 설치…"):tr("Install helper…","헬퍼 설치…")) { run { await model.installHelper() } }
                if installed { Button(tr("Remove helper…","헬퍼 제거…")) { run { await model.uninstallHelper() } } }
            }.disabled(model.helperBusy || !Self.inApplications)
            if !Self.inApplications { Text(tr("Move VibeBattery to /Applications to install the helper.","헬퍼를 설치하려면 VibeBattery를 /Applications로 옮기세요.")).font(.caption).foregroundStyle(.orange) }
            Text(tr("Or run in Terminal: \(model.helperInstallCommand)","또는 터미널에서 실행: \(model.helperInstallCommand)")).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            if Self.selfBuilt { Text(tr("Self-built copy: the installed helper will not be team-pinned.","직접 빌드한 앱: 설치되는 헬퍼가 팀 서명으로 묶이지 않습니다.")).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func run(_ work:@escaping () async -> String?) {
        Task { if let e=await work() { model.message=e } }
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
        case .vibeBattery:return tr("Set by VibeBattery","VibeBattery가 설정")
        case .external:return tr("Set by another app or system settings","다른 앱 또는 시스템 설정에서 설정")
        case .none:return tr("No limit","상한 없음")
        case .unknown:return tr("Unknown","확인 불가")
        }
    }
    var body:some View {
        Card {
            HStack { Label(tr("Charge control","충전 제어"),systemImage:"shield.lefthalf.filled").font(.headline);Spacer();Text(originText).font(.caption).foregroundStyle(.secondary) }
            Text(ChargeText.limit(model.charge)).font(model.charge.supported==false ? .callout:.system(size:27,weight:.semibold,design:.rounded))
            if let why=model.lastChangeText { Text(why).font(.callout).foregroundStyle(.secondary) }
            if !model.chargeConflicts.isEmpty {
                Label(tr("\(model.chargeConflicts.map(\.name).joined(separator:", ")) is managing charging, so VibeBattery will not change the value. Quit or delete that app to take control.","\(model.chargeConflicts.map(\.name).joined(separator:", "))이(가) 충전을 관리하고 있어 VibeBattery는 값을 바꾸지 않습니다. 해당 앱을 종료하거나 삭제하면 제어할 수 있습니다."),systemImage:"exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            HStack(spacing:12) {
                Stepper(tr("Limit \(target)%\(target==80 ? " (recommended)":"")","상한 \(target)%\(target==80 ? " (권장)":"")"),value:$target,in:ChargeCommand.range,step:5).frame(maxWidth:180)
                Button(tr("Apply","적용")) { model.applyCharge(.setLimit(target)) }.buttonStyle(.borderedProminent).disabled(!canWrite || needsHelper)
                Button(tr("Turn off limit","상한 끄기")) { model.applyCharge(.clearLimit) }.disabled(!canWrite)
            }
            if needsHelper { Text(tr("Limits below 80% are unavailable. \(helperText)","80% 미만 상한을 쓸 수 없습니다. \(helperText)")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled);HelperInstallControls() }
            HStack(spacing:12) {
                Button(tr("Charge to 100% once","한 번 100% 충전")) { model.applyCharge(.startTopUp) }.disabled(!canWrite)
                if model.topUpActive { Button(tr("End top-up","완충 종료")) { model.applyCharge(.endTopUp) }.disabled(!canWrite) }
            }
            if model.topUpActive { Text(tr("Top-up mode is on · it ends automatically when macOS turns the limit back on.","완충 모드 유지 중 · macOS가 상한을 다시 켜면 자동으로 끝납니다.")).font(.caption).foregroundStyle(.secondary) }
            else if model.topUpRequested != nil { Text(tr("Top-up requested · waiting for macOS to apply it","완충 요청됨 · macOS 반영을 기다리는 중")).font(.caption).foregroundStyle(.secondary) }
            Text(tr("Heat hold: \(model.heatStatus)","과열 보류: \(model.heatStatus)")).font(.callout)
            Text(tr("macOS keeps the limit even after you quit the app.","상한은 앱을 종료해도 macOS가 유지합니다.")).font(.caption).foregroundStyle(.secondary)
            Text(tr("A sailing lower limit, forced discharge and calibration are not offered because this macOS firmware cannot do them without cutting off the adapter. macOS decides when charging resumes.","항해 하한 지정·강제 방전·교정은 이 macOS 펌웨어에서 어댑터 차단 없이 불가능해 제공하지 않습니다. 재충전 시점은 macOS가 정합니다.")).font(.caption).foregroundStyle(.secondary)
        }.onAppear { target=model.charge.limit.map { min(100,max(50,($0+ChargeCommand.step-1)/ChargeCommand.step*ChargeCommand.step)) } ?? 80 }
    }
}
