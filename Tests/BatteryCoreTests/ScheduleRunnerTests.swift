import Testing
import Foundation
import BatteryCore
@testable import BatteryPlatform

struct ScheduleRunnerTests {
    typealias T=ChargeScheduleTests
    func file() -> JSONFile<ScheduleState> { JSONFile(url:FileManager.default.temporaryDirectory.appendingPathComponent("vb-sched-\(UUID().uuidString)").appendingPathComponent("schedule.json")) }
    let cal=T.calendar()

    @Test func firstCheckOnlySetsBaseline() {
        var calls=0;let r=ScheduleRunner(file:file()) { _,_ in calls+=1;return nil }
        #expect(r.check([T.rule(22)],now:T.at(10,22,23,0),calendar:cal)==nil)
        #expect(calls==0);#expect(r.state.lastCheck==T.at(10,22,23,0))
    }
    @Test func dueRuleRunsOnceAcrossChecks() {
        var got:[ChargeCommand]=[];let r=ScheduleRunner(file:file()) { c,_ in got.append(c);return nil }
        let rules=[T.rule(22,name:"밤")]
        _=r.check(rules,now:T.at(10,22,21,59,40),calendar:cal)
        let run=r.check(rules,now:T.at(10,22,22,0,10),calendar:cal)
        #expect(run?.result == .ran);#expect(run?.ruleName=="밤")
        #expect(r.check(rules,now:T.at(10,22,22,0,40),calendar:cal)==nil)
        #expect(got==[.setLimit(70)])
    }
    @Test func skippedOccurrenceIsRecorded() {
        var calls=0;let r=ScheduleRunner(file:file()) { _,_ in calls+=1;return nil }
        _=r.check([T.rule(10)],now:T.at(10,22,9,0),calendar:cal)
        #expect(r.check([T.rule(10)],now:T.at(10,22,23,0),calendar:cal)?.result == .skipped)
        #expect(calls==0);#expect(r.state.recent.last?.result == .skipped)
    }
    @Test func failureMessageIsRecorded() {
        let r=ScheduleRunner(file:file()) { _,_ in "다른 충전 관리 앱이 실행 중입니다" }
        _=r.check([T.rule(22)],now:T.at(10,22,21,0),calendar:cal)
        #expect(r.check([T.rule(22)],now:T.at(10,22,22,0,5),calendar:cal)?.result == .failed("다른 충전 관리 앱이 실행 중입니다"))
    }
    @Test func recentKeepsTen() {
        let r=ScheduleRunner(file:file()) { _,_ in nil };let rules=[T.rule(Set(1...7),0,0)]
        var now=T.at(10,1,0,0,30);_=r.check(rules,now:now-60,calendar:cal)
        for _ in 0..<12 { _=r.check(rules,now:now,calendar:cal);now+=86_400 }
        #expect(r.state.recent.count==10)
    }
    @Test func lastCheckIsSavedBeforeApplying() {
        let f=file();var seen:Date?
        let r=ScheduleRunner(file:f) { _,_ in seen=f.load()?.lastCheck;return nil }
        _=r.check([T.rule(22)],now:T.at(10,22,21,0),calendar:cal)
        _=r.check([T.rule(22)],now:T.at(10,22,22,0,5),calendar:cal)
        #expect(seen==T.at(10,22,22,0,5))
    }
    @Test func futureLastCheckResetsWithoutRunning() {
        var calls=0;let f=file();let r=ScheduleRunner(file:f) { _,_ in calls+=1;return nil }
        _=r.check([T.rule(22)],now:T.at(10,23,1,0),calendar:cal)
        #expect(r.check([T.rule(22)],now:T.at(10,22,23,0),calendar:cal)==nil)
        #expect(calls==0);#expect(r.state.lastCheck==T.at(10,22,23,0))
    }
    @Test func stateSurvivesRestart() {
        let f=file();_=ScheduleRunner(file:f) { _,_ in nil }.check([],now:T.at(10,22,21,0),calendar:cal)
        #expect(ScheduleRunner(file:f) { _,_ in nil }.state.lastCheck==T.at(10,22,21,0))
    }
    @Test func fileIsPrivate() throws {
        let f=file();_=ScheduleRunner(file:f) { _,_ in nil }.check([],now:T.at(10,22,21,0),calendar:cal)
        let mode=try FileManager.default.attributesOfItem(atPath:f.url.path)[.posixPermissions] as? Int
        #expect(mode==0o600)
    }
}
