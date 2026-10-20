import SwiftUI
import BatteryPlatform
struct ProcessesView:View {
    @EnvironmentObject var model:AppModel
    @State private var selection:ProcessSample?
    var body:some View {
        PageTitle(title:"앱과 프로세스",subtitle:"CPU 활동을 기준으로 정렬합니다. 실제 앱별 소비 전력이나 배터리 열화 원인을 의미하지 않습니다.")
        Card {
            Label("선택한 앱에 종료 요청",systemImage:"hand.raised").font(.headline)
            Text("시스템과 터미널은 보호합니다. 일반 백그라운드 프로세스는 활성 상태 보기에서 관리하세요. 앱을 종료하면 저장하지 않은 작업을 잃을 수 있습니다.").font(.callout).foregroundStyle(.secondary)
            Button("활성 상태 보기 열기") { model.openActivityMonitor() }
        }
        Card {
            if !model.sampled { ProgressView("측정 중 · 최대 5초 후 갱신") }
            ForEach(model.processes.prefix(30)) { p in
                HStack {
                    VStack(alignment:.leading,spacing:4) { Text(p.name).font(.body.weight(.medium));Text("PID \(p.id)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    Spacer()
                    Text(String(format:"%.1f%%",p.cpu)).monospacedDigit().frame(width:75,alignment:.trailing)
                    Text(String(format:"%.0f MB",Double(p.memory)/1048576)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width:80,alignment:.trailing)
                    Button("종료…") { selection=p }.disabled(!ProcessReader.canRequestTermination(p))
                }.padding(.vertical,5)
                Divider()
            }
        }.confirmationDialog("선택한 프로세스를 종료할까요?",isPresented:Binding(get:{selection != nil},set:{if !$0 {selection=nil}}),titleVisibility:.visible) {
            if let p=selection {
                Button("정상 종료 요청") { model.terminate(p,force:false);selection=nil }
                Button("강제 종료 · 저장하지 않은 작업 손실",role:.destructive) { model.terminate(p,force:true);selection=nil }
                Button("취소",role:.cancel) { selection=nil }
            }
        } message: { Text(selection.map { "\($0.name) · PID \($0.id)" } ?? "") }
    }
}
