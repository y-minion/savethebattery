import Foundation
import AppKit
import Combine
import ServiceManagement
import BatteryCore
import BatteryPlatform
@MainActor final class AppModel: ObservableObject {
    /// The one model, shared by the SwiftUI app and Shortcuts actions (which may launch the app in the background).
    static let shared=AppModel()
    func shortcutStatus() -> ShortcutStatus {
        battery=BatteryReader.read();refreshCharge()
        return ShortcutStatus.make(battery,limit:charge)
    }
    @Published var battery=BatterySnapshot()
    @Published var history:[BatterySnapshot]=[]
    @Published var processes:[ProcessSample]=[]
    @Published var sessions:[SessionRecord]=[]
    @Published var preferences=UserPreferences()
    @Published var message:String?
    @Published var section="dashboard"
    @Published var sampled=false
    @Published var charge=ChargeLimitState()
    @Published var chargeConflicts:[OtherChargeController]=[]
    @Published var loginItem=false
    @Published var helperStatus=HelperStatus.notInstalled
    @Published var helperBusy=false
    @Published var lowPower=ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published var lowPowerNotes:[String]=[]
    /// This Mac has no usable LED key (per launch); nothing is written again.
    @Published var ledUnsupported=false
    @Published var lowPowerBusy=false
    @Published var healthReport:HealthReport?
    @Published var sleeps:[SleepEvent]=[]
    @Published var notificationAccess=NotificationAccess.unavailable
    @Published var availableUpdate:(version:String,url:URL)?
    private var updateTimer:Timer?
    /// When the last update check started, successful or not; in memory only.
    private var lastUpdateCheck:Date?
    var openMain:(()->Void)?
    var menuStatus:MenuBarStatus { .make(onAC:battery.onAC,charging:battery.charging,heatHolding:chargeController.record.heat.holdLimit != nil) }
    var activeSessions:[SessionRecord] { sessions.filter { $0.ended==nil && ownerAlive($0) } }
    private var menuTimer:Timer?
    /// While the menu window is open the battery is read every 2 s; the 5 s tick is unchanged.
    var menuWindowOpen=false {
        didSet {
            guard menuWindowOpen != oldValue else { return }
            menuTimer?.invalidate();menuTimer=nil
            guard menuWindowOpen else { return }
            battery=BatteryReader.read();refreshLowPowerSettings()
            let t=Timer(timeInterval:2,repeats:true) { [weak self] _ in Task { @MainActor in self?.battery=BatteryReader.read() } }
            RunLoop.main.add(t,forMode:.common);menuTimer=t
        }
    }
    private let notifier=NotificationRuntime.makeSink()
    private let notificationStore=NotificationStore(url:AppPaths.notify)
    private lazy var notificationMemory=notificationStore.read()
    private var pendingHeatEvent:HeatEvent?
    private lazy var healthRecorder=HealthRecorder(store:HealthStore(url:AppPaths.health))
    private let sleepStore=SleepStore(url:AppPaths.sleep)
    private var sleepStart:BatterySnapshot?
    private var trendCache=TrendCache()
    private let helper=XPCChargeHelper()
    private var lastHeatAction=HeatAction.none
    private lazy var chargeController=ChargeController(backend:PowerUIChargeBackend(),helper:helper,detect:ChargeControllerScan.current,url:AppPaths.directory.appendingPathComponent("charge.json"))
    var chargeOrigin:LimitOrigin { charge.origin(lastWritten:chargeController.record.lastWritten) }
    var topUpRequested:Date? { chargeController.record.topUpRequested }
    var topUpActive:Bool { chargeController.topUpActive }
    @Published var scheduleRuns:[ScheduleRun]=[]
    @Published var nextSchedule:ScheduleOccurrence?
    /// Why the limit is what it is, e.g. "Schedule 'Night 70%' at 22:00 changed it".
    var lastChangeText:String? { ChargeText.currentReason(record:chargeController.record,state:charge,now:Date(),calendar:.current) }
    var chargeLog:[ChargeWrite] { chargeController.record.log }
    private lazy var scheduleRunner=ScheduleRunner(file:JSONFile(url:AppPaths.schedule)) { [weak self] command,rule in
        MainActor.assumeIsolated { self?.runSchedule(command,rule) ?? .failed(tr("The app is not available.","앱을 사용할 수 없습니다.")) }
    }
    private var controlServer:ControlServer?
    private func runSchedule(_ command:ChargeCommand,_ rule:ChargeScheduleRule) -> ScheduleApplyResult {
        switch chargeController.apply(command,source:.schedule,detail:rule.name) {
        case .success(let s):charge=s;return .applied
        case .failure(let e):return .failed(e.localizedDescription)
        }
    }
    func checkSchedules() {
        let run=scheduleRunner.check(preferences.schedules,now:Date(),calendar:.current)
        scheduleRuns=scheduleRunner.state.recent
        nextSchedule=SchedulePolicy.nextAny(preferences.schedules,after:Date(),calendar:.current)
        guard let run else { return }
        switch run.result {
        case .failed(let reason) where preferences.notifications.scheduleFailed:
            notifier.deliver(AlertEvent(id:"schedule.failed",title:tr("Schedule '\(run.ruleName)' failed","일정 '\(run.ruleName)' 실행 실패"),body:reason,section:"charge",thread:"charge"))
        case .ran where preferences.notifications.scheduleRan:
            notifier.deliver(AlertEvent(id:"schedule.ran",title:tr("Schedule '\(run.ruleName)' ran","일정 '\(run.ruleName)' 실행됨"),body:run.action,section:"charge",thread:"charge"))
        default:break
        }
    }
    func addSchedule(_ rule:ChargeScheduleRule) {
        guard preferences.schedules.count<SchedulePolicy.maxRules else { return }
        var r=rule;r.edited(now:Date());preferences.schedules.append(r);schedulesChanged()
    }
    /// Changing when or what a rule does, or turning it back on, starts it fresh so a time already past today does not fire.
    func updateSchedule(_ rule:ChargeScheduleRule) {
        guard let i=preferences.schedules.firstIndex(where:{ $0.id==rule.id }) else { return }
        let old=preferences.schedules[i];var r=rule
        if old.hour != r.hour || old.minute != r.minute || old.weekdays != r.weekdays || old.action != r.action || (!old.enabled && r.enabled) { r.edited(now:Date()) }
        preferences.schedules[i]=r;schedulesChanged()
    }
    func removeSchedule(id:UUID) { preferences.schedules.removeAll { $0.id==id };schedulesChanged() }
    private func schedulesChanged() {
        savePreferences()
        nextSchedule=SchedulePolicy.nextAny(preferences.schedules,after:Date(),calendar:.current)
    }
    static func chargeMessage(_ c:ChargeCommand,_ s:ChargeLimitState) -> String {
        c == .startTopUp ? tr("Top-up requested. macOS decides when the limit comes back.","한 번 완충을 요청했습니다. 원래 상한으로 돌아가는 시점은 macOS가 정합니다."):tr("Applied and confirmed. \(ChargeText.limit(s))","적용을 확인했습니다. \(ChargeText.limit(s))")
    }
    /// A request from vbctl or Shortcuts; applied like a user change and logged with its source.
    func perform(_ c:ChargeCommand,source:ChargeWrite.Source) -> ControlResponse {
        switch chargeController.apply(c,source:source) {
        case .success(let s):charge=s;return ControlResponse(ok:true,message:Self.chargeMessage(c,s),state:s)
        case .failure(let e):
            if c.requiresHelper { checkHelper() }
            return ControlResponse(ok:false,message:e.localizedDescription,state:charge)
        }
    }
    private func startControlServer() {
        try? FileManager.default.createDirectory(at:AppPaths.directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let server=ControlServer(path:AppPaths.controlSocket) { [weak self] c in
            MainActor.assumeIsolated { self?.perform(c,source:.cli) ?? ControlResponse(ok:false,message:tr("The app is not available.","앱을 사용할 수 없습니다."),state:nil) }
        }
        // Without the channel only vbctl writes are unavailable; the app itself keeps working.
        do { try server.start();controlServer=server } catch { controlServer=nil }
    }
    /// `pmset` runs off the main actor, and only on start, a power-state change, a menu window opening or a switch, not on the 5 s tick.
    func refreshLowPowerSettings() {
        Task { [weak self] in
            let out=await Task.detached { Self.pmsetCustom() }.value
            self?.lowPowerNotes=LowPowerText.notes(LowPowerSettings.parse(out))
        }
    }
    nonisolated private static func pmsetCustom() -> String {
        let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/pmset");p.arguments=["-g","custom"]
        let pipe=Pipe();p.standardOutput=pipe;p.standardError=FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let d=pipe.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit()
        return String(decoding:d,as:UTF8.self)
    }
    /// nil on success. The helper call and the wait for macOS to report the change stay off the main actor.
    func setLowPower(_ on:Bool) async -> String? {
        guard !lowPowerBusy else { return tr("Low Power Mode is being changed. Try again in a moment.","저전력 모드를 바꾸는 중입니다. 잠시 뒤 다시 시도해 주세요.") }
        lowPowerBusy=true;defer { lowPowerBusy=false }
        if helperStatus != .ready { await refreshHelperStatus() }
        guard helperStatus == .ready else { return LowPowerText.unavailable(helperStatus) }
        let error:String?=await Task.detached {
            if let e=XPCChargeHelper().setLowPowerMode(on) { return HelperReply.display(e) }
            for _ in 0..<20 {
                if ProcessInfo.processInfo.isLowPowerModeEnabled==on { return nil }
                try? await Task.sleep(for:.milliseconds(100))
            }
            return ProcessInfo.processInfo.isLowPowerModeEnabled==on ? nil:LowPowerText.failed
        }.value
        lowPower=ProcessInfo.processInfo.isLowPowerModeEnabled
        refreshLowPowerSettings()
        return error
    }
    // MagSafe LED. The key reads the displayed color, so success is the helper's reply, never a read-back.
    private var lastLED:MagSafeLED?
    private var ledBusy=false
    /// Bumped whenever the cache is reset, so a write that was already in flight cannot restore it.
    private var ledGeneration=0
    private var ledError:String?
    private var ledCancellable:AnyCancellable?
    private static let ledDirtyKey="vb.led.dirty"
    /// True after any non-system write, so a crash or a changed mode still returns the LED to macOS.
    private var ledDirty:Bool {
        get { UserDefaults.standard.bool(forKey:Self.ledDirtyKey) }
        set { UserDefaults.standard.set(newValue,forKey:Self.ledDirtyKey) }
    }
    /// Writes only when the target changed; the helper call stays off the main actor.
    func applyLED() {
        guard !ledBusy,!ledUnsupported,helperStatus == .ready,chargeConflicts.isEmpty else { return }
        let target=MagSafeLEDPolicy.target(preferences.led,status:menuStatus)
        guard let value=MagSafeLEDPolicy.write(target:target,last:lastLED,dirty:ledDirty,unsupported:ledUnsupported) else { return }
        ledBusy=true;let generation=ledGeneration
        // A write that times out may still land, so the flag is set before any non-system write.
        if value != .system { ledDirty=true }
        Task { @MainActor in
            let error=await Task.detached { XPCChargeHelper().setMagSafeLED(value) }.value
            ledBusy=false
            if let error {
                let outcome=MagSafeLEDPolicy.outcome(reply:error)
                if outcome.clearDirty { ledDirty=false } // nothing landed, so there is nothing to release
                if outcome.unsupported { ledUnsupported=true;return } // the card says so; no alert, no retry
                if error != ledError { ledError=error;message=HelperReply.display(error) }
                return
            }
            ledError=nil;if value == .system { ledDirty=false }
            if generation == ledGeneration { lastLED=value }
            applyLED()
        }
    }
    private func resetLEDCache() { ledGeneration+=1;lastLED=nil }
    func ledChanged() { savePreferences();applyLED() }
    /// The cable can reset the key, and the state may have changed since the last tick.
    private func watchPower() {
        ledCancellable=$battery.map(\.onAC).removeDuplicates().dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.resetLEDCache();self?.applyLED() }
        }
    }
    /// Synchronous, bounded to 1 s: the process exits right after this handler returns.
    private func releaseLED() {
        guard ledDirty,!ledUnsupported,helperStatus == .ready,chargeConflicts.isEmpty else { return }
        ledGeneration+=1 // an in-flight write must not mark state after this
        if helper.setMagSafeLED(.system,timeout:1) == nil { if !ledBusy { ledDirty=false };lastLED = .system } // a write still in flight may land later
    }
    private var helperGeneration=0
    private var helperProbe:Task<Void,Never>?
    /// The probe can wait about 3 s on an old helper, so it runs off the main actor. A call during a probe
    /// joins it, and a result is dropped when `checkHelper()` ran in the meantime.
    func refreshHelperStatus() async {
        if let t=helperProbe { await t.value;return }
        helperGeneration+=1;let g=helperGeneration
        let t=Task { @MainActor in
            let s=await Task.detached { XPCChargeHelper().status() }.value
            if g==helperGeneration && helperStatus != s { helperStatus=s;applyLED() }
            helperProbe=nil
        }
        helperProbe=t;await t.value
    }
    func checkHelper() { helperGeneration+=1;helperStatus=helper.status();applyLED() }
    func updateHealthReport() {
        let days=healthRecorder.file.days,now=Date()
        let trend=trendCache.trend(for:BatterySegment.current(days),now:now,calendar:.current)
        healthReport=HealthReport.make(snapshot:battery,days:days,sleeps:sleeps,context:AdvisorContext(limit:charge.enabled==true ? charge.limit:nil,heatEnabled:preferences.heat.enabled),now:now,calendar:.current,trend:trend)
    }
    func clearHealth() {
        do { try healthRecorder.reset();try sleepStore.delete();sleeps=[];updateHealthReport() } catch { message=error.localizedDescription }
    }
    func willSleep() {
        guard preferences.backgroundHistory else { return }
        sleepStart=BatteryReader.read();try? healthRecorder.flush()
    }
    func didWake() {
        var wake:SleepEvent?
        if let s=sleepStart, preferences.backgroundHistory {
            let e=SleepEvent(before:s,after:BatteryReader.read());wake=e
            do { try sleepStore.append(e);sleeps=sleepStore.read() } catch { message=error.localizedDescription }
        }
        sleepStart=nil;resetLEDCache();refresh(wake:wake)
        // Restarting the schedule checks now and keeps the daily timer from firing again soon after.
        if preferences.checkUpdates && UpdateCheck.isDue(last:lastUpdateCheck,now:Date()) { scheduleUpdateChecks() }
    }
    var helperInstallCommand:String { "sudo /Applications/VibeBattery.app/Contents/Resources/install-helper.sh" }
    /// Asks for the administrator password in the system dialog, then installs the root helper. Returns the text to show, or nil when the user cancelled.
    func installHelper() async -> String? { await runHelperScript("install-helper.sh",install:true) }
    func uninstallHelper() async -> String? { await runHelperScript("uninstall-helper.sh",install:false) }
    private enum ScriptOutcome { case done,cancelled,failed(String) }
    private func runHelperScript(_ name:String,install:Bool) async -> String? {
        guard !helperBusy else { return nil }
        helperBusy=true;defer { helperBusy=false }
        // Fixed path and language code only; no user input reaches the shell command.
        let command="VB_LANG=\(AppLanguage.current.rawValue) '/Applications/VibeBattery.app/Contents/Resources/\(name)'"
        let quoted=command.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"")
        let source="do shell script \"\(quoted)\" with administrator privileges"
        let outcome=await Task.detached { () -> ScriptOutcome in
            let p=Process(),err=Pipe()
            p.executableURL=URL(fileURLWithPath:"/usr/bin/osascript");p.arguments=["-e",source];p.standardError=err;p.standardOutput=FileHandle.nullDevice
            do { try p.run() } catch { return .failed(error.localizedDescription) }
            let text=String(decoding:err.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
            p.waitUntilExit()
            if p.terminationStatus==0 { return .done }
            if text.contains("(-128)") { return .cancelled } // -128: the user cancelled the password dialog
            return .failed(text.isEmpty ? tr("The helper script failed.","헬퍼 스크립트가 실패했습니다.") : text)
        }.value
        checkHelper()
        switch outcome {
        case .cancelled:return nil
        case .failed(let text):return text
        // The script ran, but the helper may still not answer; then the status line says why.
        case .done:return helperStatus.confirmation(afterInstall:install) ?? ChargeHelperText.status(self)
        }
    }
    var heatStatus:String {
        let h=preferences.heat
        if !h.enabled { return tr("Off","꺼짐") }
        let record=chargeController.record
        if record.heatPaused,let hold=record.heat.holdLimit { return tr("Stopped after a failed restore · limit left at \(hold)% (was \(record.heat.userLimit.map { "\($0)%" } ?? tr("no limit","상한 없음")))","복원 실패로 멈춤 · 상한이 \(hold)%로 남아 있음 (원래 \(record.heat.userLimit.map { "\($0)%" } ?? "상한 없음"))") }
        if record.heatPaused { return tr("Stopped · the limit was changed elsewhere or could not be applied. Turn it on again or apply a limit to resume.","멈춤 · 상한이 외부에서 바뀌었거나 적용에 실패함. 다시 켜거나 상한을 적용하면 재개") }
        if let hold=chargeController.record.heat.holdLimit { return tr("On hold · limit lowered to \(hold)%, restored after 5 minutes at or below \(Int(h.resumeAt))°C","보류 중 · 상한을 \(hold)%로 낮춤, \(Int(h.resumeAt))°C 이하 5분 유지 시 복원") }
        switch lastHeatAction {
        case .sensorUnavailable:return tr("Paused · cannot read the battery temperature","중지됨 · 배터리 온도를 읽지 못함")
        case .cannotHold(.lowCharge):return tr("Cannot hold · charge below 50%","보류 불가 · 잔량 50% 미만")
        case .cannotHold(.needsHelper):return tr("Cannot hold · the helper is needed to go below 80%","보류 불가 · 80% 미만으로 낮추려면 헬퍼가 필요")
        case .cannotHold(.limitUnknown):return tr("Cannot hold · cannot read the current charge limit","보류 불가 · 현재 충전 상한을 읽지 못함")
        default:return tr("Watching · holds charging at \(Int(h.holdAt))°C or above (only while the app is running)","감시 중 · \(Int(h.holdAt))°C 이상 충전 시 보류 (앱 실행 중에만)")
        }
    }
    func refreshCharge() {
        let step=chargeController.heatStep(snapshot:battery,settings:preferences.heat)
        lastHeatAction=step.action
        var failed=false;if case .failure?=step.result { failed=true }
        if let e=HeatEvent.from(action:step.action,failed:failed) { pendingHeatEvent=e }
        if case .failure(let e)?=step.result { message=tr("Heat hold stopped. \(e.localizedDescription) Current state: \(heatStatus)","과열 보류를 멈췄습니다. \(e.localizedDescription) 현재 상태: \(heatStatus)") }
        charge=chargeController.state();chargeConflicts=ChargeControllerScan.current()
        loginItem=SMAppService.mainApp.status == .enabled
        applyLED()
    }
    func applyCharge(_ c:ChargeCommand) {
        switch chargeController.apply(c) {
        case .success(let s):
            charge=s
            message=Self.chargeMessage(c,s)
        case .failure(let e):
            message=e.localizedDescription
            if c.requiresHelper { checkHelper() }
        }
    }
    func setHeatEnabled(_ on:Bool) {
        preferences.heat.enabled=on;if on { chargeController.resumeHeat() };savePreferences();refreshCharge()
    }
    func setLoginItem(_ on:Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { message=tr("Could not change launch at login: \(error.localizedDescription)","로그인 시 실행 설정 실패: \(error.localizedDescription)") }
        loginItem=SMAppService.mainApp.status == .enabled
    }
    private let reader=ProcessReader()
    private var timer:Timer?
    private var ticks=0
    private let historyStore=HistoryStore(url:AppPaths.directory.appendingPathComponent("history.json"))
    private let preferencesURL=AppPaths.directory.appendingPathComponent("preferences.json")
    init() {
        if let d=try? Data(contentsOf:preferencesURL),let p=try? JSONDecoder().decode(UserPreferences.self,from:d) { preferences=p;preferences.validate() }
        sleeps=sleepStore.read()
        refresh()
        checkHelper()
        watchPower()
        checkNotifications()
        startControlServer()
        NotificationRouter.shared.open={ [weak self] in self?.show($0) }
        // A heat hold must not outlive the app that would restore it.
        NotificationCenter.default.addObserver(forName:NSApplication.willTerminateNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.controlServer?.stop();_=self?.chargeController.releaseHold();self?.releaseLED();try? self?.healthRecorder.flush() }
        }
        // Permission is usually granted in System Settings; re-check when the user comes back.
        NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkNotifications();Task { await self?.refreshHelperStatus() } }
        }
        NotificationCenter.default.addObserver(forName:.NSProcessInfoPowerStateDidChange,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lowPower=ProcessInfo.processInfo.isLowPowerModeEnabled;self?.refreshLowPowerSettings() }
        }
        refreshLowPowerSettings()
        scheduleUpdateChecks()
        let ws=NSWorkspace.shared.notificationCenter
        ws.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.willSleep() } }
        ws.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.didWake() } }
        timer=Timer.scheduledTimer(withTimeInterval:5,repeats:true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    /// Checks GitHub for a newer release at launch, then daily and on wake once a day has passed, while the setting is on.
    private var currentVersion:String { ProcessInfo.processInfo.environment["VB_FAKE_CURRENT_VERSION"] ?? ReleaseClient.bundleVersion }
    func scheduleUpdateChecks() {
        updateTimer?.invalidate();updateTimer=nil
        guard preferences.checkUpdates else { availableUpdate=nil;return }
        checkForUpdate()
        updateTimer=Timer.scheduledTimer(withTimeInterval:UpdateCheck.interval,repeats:true) { [weak self] _ in Task { @MainActor in self?.checkForUpdate() } }
    }
    private func checkForUpdate() {
        lastUpdateCheck=Date()
        Task {
            let r=await ReleaseClient.latest()
            guard preferences.checkUpdates else { return }
            if let r,let v=UpdateCheck.newer(latestTag:r.tag,current:currentVersion) { availableUpdate=(v.description,r.url) }
            else if r != nil { availableUpdate=nil }
        }
    }
    func copyInstallCommand() {
        NSPasteboard.general.clearContents();NSPasteboard.general.setString(UpdateCheck.installCommand,forType:.string)
        message=tr("Install command copied. Paste it into Terminal.","설치 명령을 복사했습니다. 터미널에 붙여 넣으세요.")
    }
    func tick() {
        ticks+=1
        if ticks%6==0 { refresh();checkNotifications() }
        let visible=NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized }
        if section=="processes" && visible { processes=reader.snapshot();sampled=true }
        if section=="sessions" && visible { sessions=AppPaths.sessions.all() }
    }
    func refresh(wake:SleepEvent?=nil) {
        do { try AppPaths.sessions.removeInactive(before:Date().addingTimeInterval(-30*86400)) } catch { message=error.localizedDescription }
        battery=BatteryReader.read()
        if preferences.backgroundHistory { do { try historyStore.append(battery);try healthRecorder.record(battery) } catch { message=error.localizedDescription } }
        history=historyStore.read();sessions=AppPaths.sessions.all()
        refreshCharge()
        checkSchedules()
        updateHealthReport()
        notify(wake:wake)
    }
    func notify(wake:SleepEvent?=nil) {
        var i=NotificationInput(now:Date(),battery:battery)
        let r=chargeController.record
        i.limit=charge;i.lastWritten=r.lastWritten;i.chargeWrites=r.writes;i.topUpRequested=r.topUpRequested
        i.heatEnabled=preferences.heat.enabled;i.heatHolding=r.heat.holdLimit != nil
        i.heatStuckLimit=r.heatPaused ? r.heat.holdLimit:nil
        i.heatSensorMissing=preferences.heat.enabled && lastHeatAction == .sensorUnavailable
        i.heatEvent=pendingHeatEvent;pendingHeatEvent=nil
        i.conflicts=chargeConflicts.map(\.name)
        let store=AppPaths.sessions
        i.sessions=sessions.map { SessionSummary(id:$0.id,command:$0.command,outcome:$0.outcome,started:$0.started,ended:$0.ended,exitCode:$0.exitCode,released:store.isReleased($0.id)) }
        i.wake=wake;i.suggestions=healthReport?.suggestions ?? [];i.week=healthReport?.week
        let o=NotificationPolicy.evaluate(i,settings:preferences.notifications,memory:notificationMemory)
        notificationMemory=o.memory
        // A failed write only risks one repeated alert; the next refresh retries.
        _=try? notificationStore.save(o.memory)
        if !o.removals.isEmpty { notifier.remove(o.removals) }
        // NSApp may not exist yet during the first refresh from init.
        let front=NSApplication.shared.isActive
        for e in o.events where !(front && e.duplicatesAppMessage) { notifier.deliver(e) }
    }
    func checkNotifications() { notifier.access { [weak self] in self?.notificationAccess=$0 } }
    func requestNotifications() { notifier.request { [weak self] in self?.notificationAccess=$0 } }
    func sendTestNotification() {
        notifier.deliver(AlertEvent(id:"test",title:tr("VibeBattery test notification","VibeBattery 테스트 알림"),body:tr("Notifications are working. Click to open Settings.","알림이 정상적으로 표시됩니다. 누르면 설정 화면이 열립니다."),section:"settings",thread:"test"))
    }
    func openNotificationSettings() { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.notifications")!) }
    func show(_ s:String) { section=s;openMain?();NSApp.activate(ignoringOtherApps:true) }
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
    func clearInactiveSessions() {
        do { try AppPaths.sessions.removeInactive(before:Date());sessions=AppPaths.sessions.all() }
        catch { message=error.localizedDescription }
    }
    func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath:"/System/Applications/Utilities/Activity Monitor.app"))
    }
    func release(_ r:SessionRecord) {
        do { try AppPaths.sessions.release(r.id);sessions=AppPaths.sessions.all();message=tr("Release requested. The running command keeps running.","보호 해제를 요청했습니다. 실행 중인 명령은 계속 실행됩니다.") }
        catch { message=error.localizedDescription }
    }
    func terminate(_ p:ProcessSample,force:Bool) {
        do { try ProcessReader.terminate(p,force:force);message=tr("Quit requested. The result shows at the next reading.","종료를 요청했습니다. 다음 측정에서 결과를 확인할 수 있습니다.") }
        catch { message=error.localizedDescription }
    }
    func openBatterySettings() {
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.battery")!)
    }
    var cliPath:String { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/vbctl").path }
    func command(for executable:String) -> String {
        var parts=[ShellQuote.quote(cliPath),"run","--hours",String(format:"%g",preferences.hours)]
        if preferences.screenOff { parts.append("--screen-off") }
        if preferences.cleanup { parts.append("--cleanup") }
        parts += ["--",executable]
        return parts.joined(separator:" ")
    }
    func copyCommand(_ executable:String) {
        NSPasteboard.general.clearContents();NSPasteboard.general.setString(command(for:executable),forType:.string)
        message=tr("Command copied. Paste it into iTerm2 or Ghostty to start.","명령을 복사했습니다. iTerm2 또는 Ghostty에 붙여 넣어 시작하세요.")
    }
    func copyText(_ text:String) {
        NSPasteboard.general.clearContents();NSPasteboard.general.setString(text,forType:.string)
        message=tr("Path copied: \(text)","경로를 복사했습니다: \(text)")
    }
    func ownerAlive(_ r:SessionRecord) -> Bool { guard let o=r.owner else { return false };return ProcessReader.one(o.pid)?.identity==o }
    func status(_ r:SessionRecord) -> String {
        if r.ended==nil && !ownerAlive(r) { return tr("Managed link lost","관리 연결 끊김") }
        if r.ended==nil && AppPaths.sessions.isReleased(r.id) { return tr("Release requested","보호 해제 요청됨") }
        switch r.outcome {
        case .running:return r.protected ? tr("Protecting the task","작업 보호 중"):tr("Running","실행 중")
        case .succeeded:return tr("Done","완료")
        case .failed:return tr("Failed","실패")
        case .cancelled:return tr("Cancelled","취소")
        case .detached:return r.ended==nil ? tr("Released · task still running","보호 해제 · 작업 실행 중"):tr("Ended after release","보호 해제 후 종료")
        case .expired:return r.ended==nil ? tr("Timed out · task still running","시간 만료 · 작업 실행 중"):tr("Ended after timeout","시간 만료 후 종료")
        }
    }
}
