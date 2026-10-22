import Testing
import Foundation
import BatteryCore
@testable import BatteryPlatform
final class FakeBackend: ChargeLimitBackend {
    var state=ChargeLimitState(supported:true,enabled:true,limit:79);var accept=true;var ignore=false;var calls:[ChargeCommand]=[]
    var onRead:(()->Void)?
    /// Observed on the target: re-enabling uses macOS's own stored limit, not a helper-written one.
    var enableTo:Int?
    func read() -> ChargeLimitState { onRead?();return state }
    func perform(_ c:ChargeCommand) -> Bool {
        calls.append(c);guard accept else { return false };if ignore { return true }
        switch c {
        case .setLimit(let p):state.enabled=true;state.limit=p
        case .clearLimit:state.enabled=false
        case .endTopUp:state.enabled=true;if let e=enableTo { state.limit=e }
        case .startTopUp:break
        }
        return true
    }
}
final class FakeHelper: ChargeHelperClient {
    var isInstalled=true;let backend:FakeBackend;var calls:[Int]=[]
    init(_ b:FakeBackend) { backend=b }
    func setLimit(_ p:Int) -> String? { calls.append(p);backend.state.enabled=true;backend.state.limit=p;return nil }
}
/// Applies a helper write only after a few reads, as macOS does after the domain-change notification.
final class LateHelper: ChargeHelperClient {
    var isInstalled=true;let backend:FakeBackend;var lateReads:Int
    init(_ b:FakeBackend,lateReads:Int) { backend=b;self.lateReads=lateReads }
    func setLimit(_ p:Int) -> String? { let b=backend;b.onRead={ if self.lateReads==0 { b.state.enabled=true;b.state.limit=p } else { self.lateReads-=1 } };return nil }
}
struct ChargeControllerTests {
    func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("charge.json") }
    func make(_ b:FakeBackend,helper:FakeHelper?=nil,others:[OtherChargeController]=[],at u:URL?=nil) -> ChargeController {
        ChargeController(backend:b,helper:helper,detect:{ others },url:u ?? url(),pause:{ _ in })
    }
    func hot(_ t:Double,at now:Date) -> BatterySnapshot {
        var b=BatterySnapshot();b.timestamp=now;b.temperature=t;b.percent=85;b.onAC=true;b.charging=true;return b
    }
    var heatOn:HeatSettings { var s=HeatSettings();s.enabled=true;return s }
    @Test func conflictingControllerBlocksEveryWrite() {
        let b=FakeBackend();let c=make(b,others:[.init(name:"AlDente",evidence:"실행 중")])
        #expect(c.apply(.setLimit(80)) == .failure(.conflict(["AlDente"])))
        #expect(c.apply(.startTopUp) == .failure(.conflict(["AlDente"])))
        #expect(b.calls.isEmpty)
    }
    @Test func invalidAndUnsupportedAreRejectedWithoutWrites() {
        let b=FakeBackend();let c=make(b)
        #expect(c.apply(.setLimit(40)) == .failure(.invalid))
        b.state=ChargeLimitState(supported:false)
        #expect(c.apply(.setLimit(80)) == .failure(.unavailable))
        #expect(b.calls.isEmpty)
    }
    @Test func lowLimitsRouteToHelperAndRequireIt() {
        let b=FakeBackend();let h=FakeHelper(b)
        #expect(make(b).apply(.setLimit(70)) == .failure(.helperRequired))
        h.isInstalled=false;#expect(make(b,helper:h).apply(.setLimit(70)) == .failure(.helperRequired))
        h.isInstalled=true;let c=make(b,helper:h)
        #expect(c.apply(.setLimit(70)) == .success(ChargeLimitState(supported:true,enabled:true,limit:70)))
        #expect(h.calls==[70]);#expect(b.calls.isEmpty);#expect(c.record.lastWritten==70)
    }
    @Test func readbackMismatchIsReportedOnceWithoutRecordingOwnership() {
        let b=FakeBackend();b.ignore=true;let c=make(b)
        #expect(c.apply(.setLimit(85)) == .failure(.notApplied))
        #expect(b.calls==[.setLimit(85)]);#expect(c.record.lastWritten==nil)
    }
    @Test func helperWriteIsAcceptedOnceMacOSAppliesItLate() {
        let b=FakeBackend();b.state.limit=85;var pauses:[TimeInterval]=[]
        let c=ChargeController(backend:b,helper:LateHelper(b,lateReads:3),detect:{ [] },url:url(),pause:{ pauses.append($0) })
        #expect(c.apply(.setLimit(75)) == .success(ChargeLimitState(supported:true,enabled:true,limit:75)))
        #expect(c.record.lastWritten==75);#expect(pauses.count==3)
    }
    @Test func readbackGivesUpAfterBoundedWait() {
        let b=FakeBackend();b.ignore=true;var waited:TimeInterval=0
        let c=ChargeController(backend:b,helper:nil,detect:{ [] },url:url(),pause:{ waited+=$0 })
        #expect(c.apply(.setLimit(85)) == .failure(.notApplied))
        #expect(waited>0);#expect(waited<=5)
    }
    @Test func rejectedWriteIsReported() {
        let b=FakeBackend();b.accept=false
        #expect(make(b).apply(.clearLimit) == .failure(.rejected("macOS가 요청을 거부했습니다.")))
    }
    @Test func recordSurvivesRestart() {
        let b=FakeBackend();let u=url()
        _=make(b,at:u).apply(.setLimit(85));_=make(b,at:u).apply(.startTopUp)
        let again=make(b,at:u);#expect(again.record.lastWritten==85);#expect(again.record.topUpRequested != nil)
    }
    @Test func heatHoldSurvivesRestartAndRestoresUserLimit() {
        let b=FakeBackend();b.state.limit=90;let u=url();let t0=Date()
        let first=make(b,at:u).heatStep(snapshot:hot(40,at:t0),settings:heatOn,now:t0)
        #expect(first.action == .hold(85));#expect(b.state.limit==85)
        let restarted=make(b,at:u)
        #expect(restarted.heatStep(snapshot:hot(30,at:t0+60),settings:heatOn,now:t0+60).action == HeatAction.none)
        let done=restarted.heatStep(snapshot:hot(30,at:t0+400),settings:heatOn,now:t0+400)
        #expect(done.action == .restore(.setLimit(90)));#expect(b.state.limit==90);#expect(restarted.record.lastWritten==nil)
    }
    @Test func failedHeatHoldPausesInsteadOfRetrying() {
        let b=FakeBackend();b.state.limit=90;b.ignore=true;let c=make(b);let t0=Date()
        #expect(c.heatStep(snapshot:hot(40,at:t0),settings:heatOn,now:t0).result == .failure(.notApplied))
        #expect(c.record.heatPaused);#expect(c.record.heat==HeatState())
        #expect(c.heatStep(snapshot:hot(40,at:t0+30),settings:heatOn,now:t0+30).action == HeatAction.none)
        #expect(b.calls.count==1)
        c.resumeHeat();#expect(!c.record.heatPaused)
    }
    @Test func userApplyCancelsHoldAndHeatSkipsDuringConflict() {
        let b=FakeBackend();b.state.limit=90;let t0=Date();let c=make(b)
        _=c.heatStep(snapshot:hot(40,at:t0),settings:heatOn,now:t0)
        _=c.apply(.setLimit(95));#expect(c.record.heat==HeatState())
        let blocked=make(b,others:[.init(name:"AlDente",evidence:"")])
        #expect(blocked.heatStep(snapshot:hot(40,at:t0),settings:heatOn,now:t0).action == HeatAction.none)
        #expect(b.state.limit==95)
    }
    func holding(_ b:FakeBackend,_ c:ChargeController,_ t0:Date) {
        b.state.limit=90;_=c.heatStep(snapshot:hot(40,at:t0),settings:heatOn,now:t0)
    }
    @Test func externalChangeDuringHoldPausesHeatInsteadOfReholding() {
        let b=FakeBackend();let c=make(b);let t0=Date();holding(b,c,t0)
        b.state.limit=100
        #expect(c.heatStep(snapshot:hot(40,at:t0+30),settings:heatOn,now:t0+30).action == .yielded)
        #expect(c.heatStep(snapshot:hot(40,at:t0+60),settings:heatOn,now:t0+60).action == HeatAction.none)
        #expect(b.state.limit==100);#expect(c.record.heatPaused)
    }
    @Test func failedRestoreKeepsUserLimitAndHold() {
        let b=FakeBackend();let c=make(b);let t0=Date();holding(b,c,t0)
        b.ignore=true
        _=c.heatStep(snapshot:hot(30,at:t0+60),settings:heatOn,now:t0+60)
        #expect(c.heatStep(snapshot:hot(30,at:t0+400),settings:heatOn,now:t0+400).result == .failure(.notApplied))
        #expect(c.record.heat.holdLimit==85);#expect(c.record.heat.userLimit==90);#expect(c.record.heatPaused)
    }
    @Test func failedUserApplyKeepsHold() {
        let b=FakeBackend();let c=make(b);let t0=Date();holding(b,c,t0)
        b.accept=false
        #expect(c.apply(.setLimit(95)) == .failure(.rejected("macOS가 요청을 거부했습니다.")))
        #expect(c.record.heat.holdLimit==85);#expect(c.record.heat.userLimit==90)
    }
    @Test func topUpIsRefusedDuringHold() {
        let b=FakeBackend();let c=make(b);let t0=Date();holding(b,c,t0)
        #expect(c.apply(.startTopUp) == .failure(.heatHoldActive))
        #expect(b.calls==[.setLimit(85)])
    }
    @Test func releaseHoldRestoresUserLimitButNotExternalChange() {
        let b=FakeBackend();let c=make(b);let t0=Date();holding(b,c,t0)
        #expect(c.releaseHold() == .success(ChargeLimitState(supported:true,enabled:true,limit:90)))
        #expect(c.record.heat==HeatState())
        let other=make(b);holding(b,other,t0);b.state.limit=95
        #expect(other.releaseHold()==nil);#expect(b.state.limit==95);#expect(other.record.heat==HeatState())
    }
    @Test func restoredLimitKeepsItsOriginalOwner() {
        let b=FakeBackend();let c=make(b);let t0=Date();holding(b,c,t0)
        _=c.heatStep(snapshot:hot(30,at:t0+60),settings:heatOn,now:t0+60)
        _=c.heatStep(snapshot:hot(30,at:t0+400),settings:heatOn,now:t0+400)
        #expect(b.state.limit==90);#expect(c.record.lastWritten==nil)
        #expect(b.state.origin(lastWritten:c.record.lastWritten) == .external)
        let own=make(b);_=own.apply(.setLimit(90));holding(b,own,t0)
        #expect(own.releaseHold() != nil);#expect(own.record.lastWritten==90)
    }
    @Test func topUpEndsWhenMacOSReEnablesTheLimit() {
        let b=FakeBackend();b.state.limit=80;let c=make(b)
        _=c.apply(.startTopUp);#expect(c.record.topUpRequested != nil)
        #expect(c.state().enabled==true);#expect(c.record.topUpRequested != nil)
        b.state.enabled=false;_=c.state();#expect(c.topUpActive)
        b.state.enabled=true;_=c.state()
        #expect(c.record.topUpRequested==nil);#expect(!c.topUpActive)
    }
    /// Observed on the target: during a one-time full charge PowerUI reports enabled with a 100% limit.
    @Test func topUpIsSeenAsAFullLimitAndEndsWhenTheOldLimitReturns() {
        let b=FakeBackend();b.state.limit=70;let c=make(b)
        _=c.apply(.startTopUp)
        b.state=ChargeLimitState(supported:true,enabled:true,limit:100);_=c.state()
        #expect(c.topUpActive)
        b.state.limit=70;_=c.state()
        #expect(c.record.topUpRequested==nil);#expect(!c.topUpActive)
    }
    @Test func endTopUpIsConfirmedOnlyBelowAFullLimit() {
        #expect(ChargeLimitState(supported:true,enabled:true,limit:100).matches(.endTopUp)==false)
        #expect(ChargeLimitState(supported:true,enabled:true,limit:70).matches(.endTopUp)==true)
    }
    @Test func everyWriteIsLoggedWithItsSourceAndKeptBounded() {
        let b=FakeBackend();let c=make(b)
        _=c.apply(.clearLimit)
        #expect(c.record.log.last?.command=="clearLimit");#expect(c.record.log.last?.source == .user);#expect(c.record.log.last?.ok==true)
        b.ignore=true;_=c.apply(.setLimit(85))
        #expect(c.record.log.last?.ok==false)
        b.ignore=false;for _ in 0..<30 { _=c.apply(.setLimit(90)) }
        #expect(c.record.log.count==ChargeRecord.logLimit)
    }
    @Test func automaticWritesAreLoggedAsHeatOrQuit() {
        let b=FakeBackend();let c=make(b);let t0=Date();holding(b,c,t0)
        #expect(c.record.log.last?.source == .heat)
        _=c.releaseHold()
        #expect(c.record.log.last?.source == .quit)
    }
    @Test func endingTopUpReappliesTheUsersLowLimit() {
        let b=FakeBackend();b.enableTo=80;let h=FakeHelper(b);let c=make(b,helper:h)
        _=c.apply(.setLimit(70));_=c.apply(.startTopUp)
        b.state.limit=100;_=c.state()
        #expect(c.apply(.endTopUp) == .success(ChargeLimitState(supported:true,enabled:true,limit:70)))
        #expect(h.calls==[70,70]);#expect(c.record.lastWritten==70);#expect(c.record.log.last?.source == .topUp)
    }
    @Test func macOSEndingTopUpReappliesTheUsersLowLimit() {
        let b=FakeBackend();let h=FakeHelper(b);let c=make(b,helper:h)
        _=c.apply(.setLimit(70));_=c.apply(.startTopUp)
        b.state.limit=100;_=c.state();#expect(c.topUpActive)
        b.state.limit=80
        #expect(c.state().limit==70);#expect(c.record.topUpRequested==nil);#expect(h.calls==[70,70])
    }
    @Test func helperStatusExplainsWhySubEightyIsUnavailable() {
        var probes=0
        let probe={ probes+=1;return true }
        #expect(HelperStatus.evaluate(installed:false,appPath:"/Applications/VibeBattery.app",probe:probe) == .notInstalled)
        #expect(HelperStatus.evaluate(installed:true,appPath:"/Users/u/dist/VibeBattery.app",probe:probe) == .wrongLocation)
        #expect(probes==0)
        #expect(HelperStatus.evaluate(installed:true,appPath:"/Applications/VibeBattery.app",probe:{ false }) == .unreachable)
        #expect(HelperStatus.evaluate(installed:true,appPath:"/Applications/VibeBattery.app/",probe:probe) == .ready)
        #expect(probes==1)
    }
}
