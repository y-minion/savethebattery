import Testing
import Foundation
@testable import BatteryCore
struct NotificationProtectTests {
    func hot(_ dt:Double,_ t:Double,ac:Bool=true) -> NotificationInput { NT.input(dt,onAC:ac,temp:t) }
    @Test func highTemperatureFiresOnceAndRearmsAfterCooling() {
        let r=NT.run([hot(0,40),hot(30,41),hot(60,36.9),hot(600,40),hot(1860,40)])
        #expect(NT.ids(r)==[["protect.heat"],[],[],[],["protect.heat"]]);#expect(r[2].removals==["protect.heat"])
        #expect(r[0].events[0].title=="배터리 40.0°C");#expect(r[0].events[0].section=="settings")
    }
    @Test func onBatteryThresholdIsTwoDegreesHigher() {
        #expect(NT.ids(NT.run([hot(0,41,ac:false),hot(30,42,ac:false)]))==[[],["protect.heat"]])
    }
    @Test func staleMissingOrBatterylessTemperatureIsIgnored() {
        var stale=hot(0,50);stale.battery.timestamp=NT.t0-200
        var desktop=hot(0,50);desktop.battery.percent=nil
        var none=hot(0,30);none.battery.temperature=nil
        for x in [stale,desktop,none] { #expect(NT.ids(NT.run([x]))==[[]]) }
    }
    @Test func conflictAnnouncesNewNamesAndClearsWhenGone() {
        var a=NT.input(0);a.conflicts=["AlDente"]
        var b=NT.input(30);b.conflicts=["AlDente"]
        var c=NT.input(60);c.conflicts=["AlDente","batt"]
        let r=NT.run([a,b,c,NT.input(90)])
        #expect(NT.ids(r)==[["protect.conflict"],[],["protect.conflict"],[]])
        #expect(r[0].events[0].body.contains("AlDente"));#expect(r[2].events[0].body.contains("batt"));#expect(r[3].removals==["protect.conflict"])
        #expect(r[0].events[0].section=="dashboard")
    }
    @Test func stuckHoldRepeatsDailyUntilResolved() {
        var a=NT.input(0);a.heatStuckLimit=60
        var b=NT.input(3600);b.heatStuckLimit=60
        var c=NT.input(86400+10);c.heatStuckLimit=60
        let r=NT.run([a,b,c,NT.input(86400+40)])
        #expect(NT.ids(r)==[["heat.stuck"],[],["heat.stuck"],[]]);#expect(r[3].removals==["heat.stuck"])
        #expect(r[0].events[0].body.contains("60%"))
    }
    @Test func heatEventsMapToAlerts() {
        func one(_ e:HeatEvent) -> [AlertEvent] { var i=NT.input(0);i.heatEvent=e;return NT.run([i])[0].events }
        #expect(one(.yielded).map(\.id)==["heat.paused"]);#expect(one(.yielded)[0].duplicatesAppMessage)
        #expect(one(.holdFailed).map(\.id)==["heat.failed"]);#expect(one(.holdFailed)[0].duplicatesAppMessage)
        #expect(one(.held(70)).map(\.id)==["heat.activity"]);#expect(one(.held(70))[0].body.contains("70%"))
        #expect(one(.restored).map(\.id)==["heat.activity"])
        var quiet=NT.all;quiet.heatActivity=false
        var i=NT.input(0);i.heatEvent = .held(70)
        #expect(NT.run([i],quiet)[0].events.isEmpty)
    }
    @Test func missingSensorAnnouncedAfterTenMinutes() {
        func m(_ dt:Double) -> NotificationInput { var i=NT.input(dt,temp:nil);i.heatSensorMissing=true;return i }
        let r=NT.run([m(0),m(300),m(600),m(900),NT.input(930)])
        #expect(NT.ids(r)==[[],[],["heat.sensor"],[],[]]);#expect(r[4].removals==["heat.sensor"])
    }
}
