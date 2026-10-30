import Testing
import Foundation
@testable import BatteryCore
struct NotificationHealthTests {
    func sleep(hours:Double,from:Int,to:Int) -> SleepEvent {
        var a=BatterySnapshot();a.timestamp=NT.t0-hours*3600;a.percent=from
        var b=BatterySnapshot();b.timestamp=NT.t0;b.percent=to
        return SleepEvent(before:a,after:b)
    }
    @Test func highSleepDrainAnnouncedOnWake() {
        AppLanguage.$forced.withValue(.ko) {
            var i=NT.input(0);i.wake=sleep(hours:2,from:80,to:74)
            let r=NT.run([i]);#expect(NT.ids(r)==[["health.sleep"]]);#expect(r[0].events[0].section=="health")
            #expect(r[0].events[0].body.contains("3.0%"))
            var calm=NT.input(0);calm.wake=sleep(hours:8,from:80,to:78)
            #expect(NT.ids(NT.run([calm]))==[[]])
        }
    }
    @Test func suggestionsRepeatAtMostWeekly() {
        AppLanguage.$forced.withValue(.ko) {
            func g(_ dt:Double) -> NotificationInput { var i=NT.input(dt);i.suggestions=[Suggestion(kind:.chargeLimit,message:"상한 80% 권장")];return i }
            let r=NT.run([g(0),g(86400),g(7*86400)])
            #expect(NT.ids(r)==[["health.suggestion.chargeLimit"],[],["health.suggestion.chargeLimit"]])
            #expect(r[0].events[0].body=="상한 80% 권장")
        }
    }
    @Test func weeklySummaryOncePerWeekAfterMondayNine() {
        AppLanguage.$forced.withValue(.ko) {
            func w(_ dt:Double) -> NotificationInput { var i=NT.input(dt);var u=UsageSummary();u.observed=3600;u.soc95=7200;i.week=u;return i }
            // t0 is Monday 14:13:20 UTC: next Monday 09:00 is 7 days − 51 200 s + 32 400 s later.
            let nextMonday9:Double=586_000
            let r=NT.run([w(0),w(86400),w(nextMonday9-60),w(nextMonday9)])
            #expect(NT.ids(r)==[["health.weekly"],[],[],["health.weekly"]])
            #expect(r[0].memory.weekKey=="2026-W39");#expect(r[3].memory.weekKey=="2026-W40")
            #expect(r[0].events[0].body.contains("2.0시간"))
            var empty=NT.input(0);empty.week=UsageSummary()
            #expect(NT.ids(NT.run([empty]))==[[]])
        }
    }
    @Test func disabledEventsStillAdvanceMemory() {
        AppLanguage.$forced.withValue(.ko) {
            var off=NT.all;off.highTemperature=false
            let first=NotificationPolicy.evaluate(NT.input(0,temp:41),settings:off,memory:NotificationMemory())
            #expect(first.events.isEmpty);#expect(!first.memory.hotArmed)
            #expect(NotificationPolicy.evaluate(NT.input(30,temp:41),settings:NT.all,memory:first.memory).events.isEmpty)
        }
    }
    @Test func timestampsFromTheFutureCountAsExpired() {
        AppLanguage.$forced.withValue(.ko) {
            var m=NotificationMemory();m.hotSent=NT.t0+86400
            #expect(NT.ids(NT.run([NT.input(0,temp:41)],memory:m))==[["protect.heat"]])
            var g=NotificationMemory();g.suggestionSent["chargeLimit"]=NT.t0+86400
            var i=NT.input(0);i.suggestions=[Suggestion(kind:.chargeLimit,message:"x")]
            #expect(NT.ids(NT.run([i],memory:g))==[["health.suggestion.chargeLimit"]])
        }
    }
}
