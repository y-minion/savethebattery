import Foundation
import AppKit
import Combine
import BatteryCore
import BatteryPlatform
@MainActor final class AppModel: ObservableObject {
    @Published var battery=BatterySnapshot()
    @Published var history:[BatterySnapshot]=[]
    @Published var processes:[ProcessSample]=[]
    @Published var sessions:[SessionRecord]=[]
    @Published var preferences=UserPreferences()
    @Published var message:String?
    @Published var section="dashboard"
    @Published var sampled=false
    private let reader=ProcessReader()
    private var timer:Timer?
    private var ticks=0
    private let historyStore=HistoryStore(url:AppPaths.directory.appendingPathComponent("history.json"))
    private let preferencesURL=AppPaths.directory.appendingPathComponent("preferences.json")
    init() {
        if let d=try? Data(contentsOf:preferencesURL),let p=try? JSONDecoder().decode(UserPreferences.self,from:d) { preferences=p;preferences.validate() }
        refresh()
        timer=Timer.scheduledTimer(withTimeInterval:5,repeats:true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    func tick() {
        ticks+=1
        if ticks%6==0 { refresh() }
        let visible=NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized }
        if section=="processes" && visible { processes=reader.snapshot();sampled=true }
        if section=="sessions" && visible { sessions=AppPaths.sessions.all() }
    }
    func refresh() {
        battery=BatteryReader.read()
        if preferences.backgroundHistory { do { try historyStore.append(battery) } catch { message=error.localizedDescription } }
        history=historyStore.read();sessions=AppPaths.sessions.all()
    }
    func savePreferences() {
        preferences.validate()
        do {
            try FileManager.default.createDirectory(at:AppPaths.directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try JSONEncoder().encode(preferences).write(to:preferencesURL,options:.atomic)
        } catch { message=error.localizedDescription }
    }
    func clearHistory() {
        do { try historyStore.delete();history=[] } catch { message=error.localizedDescription }
    }
    func release(_ r:SessionRecord) {
        do { try AppPaths.sessions.release(r.id);sessions=AppPaths.sessions.all();message="보호 해제를 요청했습니다. 실행 중인 명령은 계속 실행됩니다." }
        catch { message=error.localizedDescription }
    }
    func terminate(_ p:ProcessSample,force:Bool) {
        do { try ProcessReader.terminate(p,force:force);message="종료를 요청했습니다. 다음 측정에서 결과를 확인할 수 있습니다." }
        catch { message=error.localizedDescription }
    }
    func openBatterySettings() {
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.battery")!)
    }
    var cliPath:String { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/vibebattery").path }
    func command(for executable:String) -> String {
        var parts=[ShellQuote.quote(cliPath),"run","--hours",String(format:"%g",preferences.hours)]
        if preferences.screenOff { parts.append("--screen-off") }
        if preferences.cleanup { parts.append("--cleanup") }
        parts += ["--",executable]
        return parts.joined(separator:" ")
    }
    func copyCommand(_ executable:String) {
        NSPasteboard.general.clearContents();NSPasteboard.general.setString(command(for:executable),forType:.string)
        message="명령을 복사했습니다. iTerm2 또는 Ghostty에 붙여 넣어 시작하세요."
    }
    func ownerAlive(_ r:SessionRecord) -> Bool { guard let o=r.owner else { return false };return ProcessReader.one(o.pid)?.identity==o }
    func status(_ r:SessionRecord) -> String {
        if r.ended==nil && !ownerAlive(r) { return "관리 연결 끊김" }
        if r.ended==nil && AppPaths.sessions.isReleased(r.id) { return "보호 해제 요청됨" }
        switch r.outcome {
        case .running:return r.protected ? "작업 보호 중":"실행 중"
        case .succeeded:return "완료"
        case .failed:return "실패"
        case .cancelled:return "취소"
        case .detached:return r.ended==nil ? "보호 해제 · 작업 실행 중":"보호 해제 후 종료"
        case .expired:return r.ended==nil ? "시간 만료 · 작업 실행 중":"시간 만료 후 종료"
        }
    }
}
