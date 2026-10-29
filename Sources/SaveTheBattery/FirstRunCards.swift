import SwiftUI
import BatteryCore
import BatteryPlatform
/// Shown while the app runs from anywhere but Applications, where the helper and updates do not work.
struct MoveToApplicationsCard:View {
    @EnvironmentObject var model:AppModel
    private var folder:String { FileManager.default.displayName(atPath:AppLocation.original().deletingLastPathComponent().path) }
    var body:some View {
        Card {
            Label(tr("Move Save the Battery to Applications","Save the Battery를 응용 프로그램 폴더로 옮기세요"),systemImage:"folder.badge.plus").font(.headline)
            Text(tr("It is running from \(folder). The helper and in-app updates only work from the Applications folder.","지금은 \(folder)에서 실행 중입니다. 헬퍼와 앱 안 업데이트는 응용 프로그램 폴더에서만 동작합니다.")).foregroundStyle(.secondary)
            if AppLocation.applicationsWritable {
                HStack(spacing:12) {
                    Button(tr("Move to Applications","응용 프로그램으로 옮기기")) { model.moveToApplications() }.buttonStyle(.borderedProminent)
                    Button(tr("Not now","나중에")) { model.moveCardDismissed=true }
                }
                Text(tr("The app restarts from Applications. A copy in Downloads goes to the Trash; the disk image is left alone.","앱이 응용 프로그램 폴더에서 다시 시작됩니다. 다운로드 폴더의 사본은 휴지통으로 옮기고, 디스크 이미지는 그대로 둡니다.")).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(tr("This account cannot write to Applications. Ask an administrator to move the app there.","이 계정은 응용 프로그램 폴더에 쓸 수 없습니다. 관리자에게 앱을 옮겨 달라고 요청하세요.")).font(.callout).foregroundStyle(.orange)
            }
        }
    }
}
/// The recommended first step; 80% needs no helper.
struct LimitTipCard:View {
    @EnvironmentObject var model:AppModel
    var body:some View {
        Card {
            Label(tr("Recommended: stop charging at 80%","권장: 80%에서 충전 멈추기"),systemImage:"leaf.fill").font(.headline).foregroundStyle(.mint)
            Text(tr("Lithium-ion batteries age faster when they stay full. macOS keeps this limit even when the app is closed.","리튬 이온 배터리는 가득 찬 채로 오래 있으면 더 빨리 낡습니다. 앱을 종료해도 macOS가 이 상한을 지킵니다.")).foregroundStyle(.secondary)
            HStack(spacing:12) {
                Button(tr("Set 80%","80%로 설정")) { model.applyCharge(.setLimit(80)) }.buttonStyle(.borderedProminent)
                Button(tr("Not now","나중에")) { model.dismissLimitTip() }
            }
        }
    }
}
