import Testing
import Foundation
@testable import BatteryCore
struct NotificationChargeTests {
    func at(_ dt:Double,_ p:Int,ac:Bool=true,charging:Bool=false) -> NotificationInput { NT.input(dt,percent:p,onAC:ac,charging:charging) }
    @Test func limitReachedWhenChargingStopsNearLimit() {
        let r=NT.run([at(0,78,charging:true),at(30,79),at(60,80)])
        #expect(NT.ids(r)==[[],["charge.limitReached"],[]])
        #expect(r[1].events[0].title.contains("80%"));#expect(r[1].events[0].section=="dashboard")
    }
    @Test func limitReachedNeedsAnObservedChargingStep() {
        #expect(NT.ids(NT.run([at(0,80)]))==[[]])
        // A gap (sleep, app closed) is a fresh baseline.
        #expect(NT.ids(NT.run([at(0,78,charging:true),at(400,80)]))==[[],[]])
    }
    @Test func limitReachedSkippedDuringHeatHoldAndTopUp() {
        var a=at(30,80);a.heatHolding=true
        #expect(NT.ids(NT.run([at(0,79,charging:true),a]))==[[],[]])
        var b=at(30,80);b.topUpRequested=NT.t0
        #expect(!NT.ids(NT.run([at(0,79,charging:true),b])).flatMap { $0 }.contains("charge.limitReached"))
    }
    @Test func limitReachedRearmsOnlyAfterLongUnplugOrNewLimit() {
        let brief=NT.run([at(0,79,charging:true),at(30,80),at(60,80,ac:false),at(90,79,charging:true),at(120,80)])
        #expect(NT.ids(brief).flatMap { $0 }==["charge.limitReached"])
        let long=NT.run([at(0,79,charging:true),at(30,80),at(60,80,ac:false),at(390,79,ac:false),at(420,79,charging:true),at(450,80)])
        #expect(NT.ids(long).flatMap { $0 }==["charge.limitReached","charge.limitReached"])
        var raised=at(90,84,charging:true);raised.limit.limit=85;raised.lastWritten=85
        var stop=at(120,85);stop.limit.limit=85;stop.lastWritten=85
        #expect(NT.ids(NT.run([at(0,79,charging:true),at(30,80),raised,stop])).flatMap { $0 }==["charge.limitReached","charge.limitReached"])
    }
    @Test func topUpDoneOncePerRequest() {
        func t(_ dt:Double,_ p:Int,_ requested:Double,charging:Bool=false) -> NotificationInput {
            var i=at(dt,p,charging:charging);i.topUpRequested=NT.t0+requested;i.limit.enabled=false;return i
        }
        let r=NT.run([t(0,98,0,charging:true),t(30,99,0,charging:true),t(60,100,0),t(90,100,90)])
        #expect(NT.ids(r)==[[],["charge.topUpDone"],[],["charge.topUpDone"]])
    }
    @Test func lowBatteryRearmsAfterRiseOrSteadyAdapter() {
        let r=NT.run([at(0,25,ac:false),at(30,20,ac:false),at(60,19,ac:false),at(90,19),at(120,19,ac:false),at(150,18,ac:false),at(180,19),at(330,20),at(360,20,ac:false)])
        #expect(NT.ids(r)==[[],["charge.low"],[],[],[],[],[],[],["charge.low"]])
        #expect(r[7].removals==["charge.low"])
        let rise=NT.run([at(0,20,ac:false),at(30,24,ac:false),at(60,25,ac:false),at(90,20,ac:false)])
        #expect(NT.ids(rise)==[["charge.low"],[],[],["charge.low"]])
    }
    @Test func limitChangedOnlyWhenSomeoneElseChangesIt() {
        var ext=at(30,60);ext.limit.limit=90
        let r=NT.run([at(0,60),ext]);#expect(NT.ids(r)==[[],["charge.limitChanged"]]);#expect(r[1].events[0].title.contains("90%"))
        var off=at(30,60);off.limit.enabled=false
        #expect(NT.ids(NT.run([at(0,60),off]))==[[],["charge.limitChanged"]])
        var mine=at(30,60);mine.limit.enabled=false;mine.lastWritten=nil
        var topUp=at(30,60);topUp.limit.enabled=false;topUp.topUpRequested=NT.t0
        var yielded=at(30,60);yielded.limit.limit=90;yielded.heatEvent = .yielded
        var restored=at(30,60);restored.limit.limit=90;restored.lastWritten=nil
        for x in [mine,topUp,yielded,restored] { #expect(!NT.ids(NT.run([at(0,60),x])).flatMap { $0 }.contains("charge.limitChanged")) }
        var unknown=at(30,60);unknown.limit.supported=nil
        var back=at(60,60);back.limit.limit=90
        #expect(NT.ids(NT.run([at(0,60),unknown,back]))==[[],[],["charge.limitChanged"]])
        let again=NT.run([at(0,60),ext,at(60,60)]);#expect(again[2].removals==["charge.limitChanged"])
    }
    @Test func controlUnavailableOnlyAfterSupportWasSeen() {
        var no=at(0,60);no.limit=ChargeLimitState(supported:false)
        #expect(NT.ids(NT.run([no]))==[[]])
        var later=at(30,60);later.limit=ChargeLimitState(supported:false)
        var again=at(60,60);again.limit=ChargeLimitState(supported:false)
        let r=NT.run([at(0,60),later,again,at(90,60)])
        #expect(NT.ids(r)==[[],["charge.unavailable"],[],[]]);#expect(r[3].removals==["charge.unavailable"])
    }
}
