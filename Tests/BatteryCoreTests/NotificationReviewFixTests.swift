import Testing
import Foundation
@testable import BatteryCore
@testable import BatteryPlatform
struct NotificationReviewFixTests {
    func at(_ dt:Double,limit:Int=80,enabled:Bool=true,written:Int?=80,writes:Int=1) -> NotificationInput {
        var i=NT.input(dt);i.limit=ChargeLimitState(supported:true,enabled:enabled,limit:limit);i.lastWritten=written;i.chargeWrites=writes;return i
    }
    @Test func ownRestoreWithUnchangedLastWrittenIsNotAnnounced() {
        // The user's 90% came from System Settings; a hold wrote 80 (same as the stale lastWritten), then restored 90.
        var restored=at(90,limit:90,writes:3);restored.heatEvent = .restored
        let r=NT.run([at(0),at(30,limit:90),at(60,writes:2),restored])
        #expect(NT.ids(r)[1]==["charge.limitChanged"]);#expect(!NT.ids(r)[2...].flatMap { $0 }.contains("charge.limitChanged"))
    }
    @Test func chargeWritesCountEveryAttempt() {
        let b=FakeBackend();let u=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("charge.json")
        let c=ChargeController(backend:b,helper:nil,detect:{ [] },url:u)
        _=c.apply(.setLimit(80));#expect(c.record.writes==1)
        b.ignore=true;#expect(c.apply(.setLimit(85)) == .failure(.notApplied));#expect(c.record.writes==2)
        #expect(c.apply(.setLimit(83)) == .failure(.invalid));#expect(c.record.writes==2)
        let blocked=ChargeController(backend:b,helper:nil,detect:{ [.init(name:"AlDente",evidence:"x")] },url:u.appendingPathExtension("b"))
        _=blocked.apply(.setLimit(80));#expect(blocked.record.writes==0)
    }
    @Test func staleTopUpRequestStopsMutingAlerts() {
        var off=at(30,enabled:false);off.topUpRequested=NT.t0-25*3600
        #expect(NT.ids(NT.run([at(0),off]))==[[],["charge.limitChanged"]])
        var charging=NT.input(0,percent:78,charging:true);charging.topUpRequested=NT.t0-25*3600
        var stop=NT.input(30,percent:80);stop.topUpRequested=NT.t0-25*3600
        #expect(NT.ids(NT.run([charging,stop])).flatMap { $0 }.contains("charge.limitReached"))
    }
    @Test func oldEndingsAfterRestartAreNotAnnounced() {
        let id=UUID();var m=NotificationMemory();m.sessions[id.uuidString]=SessionMark()
        var i=NT.input(0);i.sessions=[SessionSummary(id:id,command:"claude",outcome:.succeeded,started:NT.t0-6*3600,ended:NT.t0-3*3600,exitCode:0)]
        let r=NT.run([i],memory:m)
        #expect(NT.ids(r)==[[]]);#expect(r[0].memory.sessions[id.uuidString]?.ended==true)
    }
    @Test func pausedHoldIsAnnouncedEvenWithTheAppInFront() {
        var i=NT.input(0);i.heatEvent = .yielded
        #expect(NT.run([i])[0].events.first?.duplicatesAppMessage==false)
    }
}
