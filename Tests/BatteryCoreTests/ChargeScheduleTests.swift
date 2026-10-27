import Testing
import Foundation
@testable import BatteryCore

struct ChargeScheduleTests {
    static func calendar(_ zone:String="Asia/Seoul") -> Calendar { var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:zone)!;return c }
    /// 2026-10-22 is a Thursday.
    static func at(_ month:Int,_ day:Int,_ hour:Int,_ minute:Int,_ second:Int=0,zone:String="Asia/Seoul") -> Date {
        calendar(zone).date(from:DateComponents(year:2026,month:month,day:day,hour:hour,minute:minute,second:second))!
    }
    static let past=Date(timeIntervalSince1970:0)
    static func rule(_ days:Set<Int>,_ hour:Int,_ minute:Int=0,_ action:ScheduleAction = .setLimit(70),name:String="r",enabled:Bool=true,since:Date=past) -> ChargeScheduleRule {
        ChargeScheduleRule(id:UUID(),name:name,weekdays:days,hour:hour,minute:minute,action:action,enabled:enabled,activeSince:since)
    }
    /// Every day.
    static func rule(_ hour:Int,_ minute:Int=0,_ action:ScheduleAction = .setLimit(70),name:String="r",enabled:Bool=true,since:Date=past) -> ChargeScheduleRule {
        rule(Set(1...7),hour,minute,action,name:name,enabled:enabled,since:since)
    }
    let cal=Self.calendar()

    @Test func nextOccurrenceRespectsWeekdays() {
        AppLanguage.$forced.withValue(.ko) {
            let r=Self.rule(Set(2...6),7)
            #expect(SchedulePolicy.next(r,after:Self.at(10,23,8,0),calendar:cal)==Self.at(10,26,7,0))
        }
    }
    @Test func weekBoundary() {
        AppLanguage.$forced.withValue(.ko) {
            let r=Self.rule(Set(1...7),0)
            #expect(SchedulePolicy.due([r],lastCheck:Self.at(10,25,23,59),now:Self.at(10,26,0,0,30),calendar:cal) == .run(ScheduleOccurrence(rule:r,at:Self.at(10,26,0,0))))
        }
    }
    @Test func latestOfManyWins() {
        AppLanguage.$forced.withValue(.ko) {
            let a=Self.rule(21),b=Self.rule(22)
            #expect(SchedulePolicy.due([b,a],lastCheck:Self.at(10,22,20,0),now:Self.at(10,22,23,0),calendar:cal) == .run(ScheduleOccurrence(rule:b,at:Self.at(10,22,22,0))))
        }
    }
    @Test func sameTimeLaterInListWins() {
        AppLanguage.$forced.withValue(.ko) {
            let a=Self.rule(22,name:"a"),b=Self.rule(22,name:"b")
            #expect(SchedulePolicy.due([a,b],lastCheck:Self.at(10,22,21,0),now:Self.at(10,22,22,1),calendar:cal) == .run(ScheduleOccurrence(rule:b,at:Self.at(10,22,22,0))))
        }
    }
    @Test func catchUpWindowBoundary() {
        AppLanguage.$forced.withValue(.ko) {
            let r=Self.rule(10),o=ScheduleOccurrence(rule:r,at:Self.at(10,22,10,0))
            #expect(SchedulePolicy.due([r],lastCheck:Self.at(10,22,9,0),now:Self.at(10,22,21,59),calendar:cal) == .run(o))
            #expect(SchedulePolicy.due([r],lastCheck:Self.at(10,22,9,0),now:Self.at(10,22,22,1),calendar:cal) == .skip(o))
        }
    }
    @Test func firstCheckIsBaseline() {
        AppLanguage.$forced.withValue(.ko) {
            #expect(SchedulePolicy.due([Self.rule(22)],lastCheck:nil,now:Self.at(10,22,23,0),calendar:cal) == ScheduleDecision.none)
        }
    }
    @Test func clockBackwardsRunsNothing() {
        AppLanguage.$forced.withValue(.ko) {
            #expect(SchedulePolicy.due([Self.rule(22)],lastCheck:Self.at(10,23,1,0),now:Self.at(10,22,23,0),calendar:cal) == ScheduleDecision.none)
        }
    }
    @Test func disabledRuleIgnored() {
        AppLanguage.$forced.withValue(.ko) {
            #expect(SchedulePolicy.due([Self.rule(22,enabled:false)],lastCheck:Self.at(10,22,21,0),now:Self.at(10,22,23,0),calendar:cal) == ScheduleDecision.none)
        }
    }
    @Test func activeSinceLimitsCatchUp() {
        AppLanguage.$forced.withValue(.ko) {
            let r=Self.rule(22,since:Self.at(10,22,22,30))
            #expect(SchedulePolicy.due([r],lastCheck:Self.at(10,22,21,0),now:Self.at(10,22,23,0),calendar:cal) == ScheduleDecision.none)
        }
    }
    @Test func editedRuleDoesNotFireForPastTimeToday() {
        AppLanguage.$forced.withValue(.ko) {
            // The app was off since 08:00; at 15:00:05 the user moves a rule to 09:00.
            var r=Self.rule(14);r.hour=9;r.edited(now:Self.at(10,22,15,0,5))
            #expect(SchedulePolicy.due([r],lastCheck:Self.at(10,22,8,0),now:Self.at(10,22,15,0,10),calendar:cal) == ScheduleDecision.none)
        }
    }
    @Test func dstSpringForwardRunsOnce() {
        AppLanguage.$forced.withValue(.ko) {
            let ny=Self.calendar("America/New_York"),r=Self.rule(2,30)
            let from=ny.date(from:DateComponents(year:2026,month:3,day:8,hour:1))!,to=ny.date(from:DateComponents(year:2026,month:3,day:8,hour:4))!
            guard case .run=SchedulePolicy.due([r],lastCheck:from,now:to,calendar:ny) else { Issue.record("expected one run");return }
            #expect(SchedulePolicy.due([r],lastCheck:to,now:to+60,calendar:ny) == ScheduleDecision.none)
        }
    }
    @Test func timeZoneChangeRunsAtMostOnce() {
        AppLanguage.$forced.withValue(.ko) {
            let r=Self.rule(22),start=Self.at(10,22,21,50),mid=Self.at(10,22,22,20)
            // Flying to London between checks: Seoul's 22:00 is not London's 22:00.
            #expect(SchedulePolicy.due([r],lastCheck:start,now:mid,calendar:Self.calendar("Europe/London")) == ScheduleDecision.none)
            // Back in Seoul, the 22:00 that passed before the last check does not run late.
            #expect(SchedulePolicy.due([r],lastCheck:mid,now:mid+60,calendar:cal) == ScheduleDecision.none)
        }
    }
    @Test func sentenceReadsPlainly() {
        AppLanguage.$forced.withValue(.ko) {
            #expect(ScheduleText.sentence(Self.rule(Set(2...6),22,0,.setLimit(70)))=="평일 22:00 · 상한 70%")
            #expect(ScheduleText.days(Set(1...7))=="매일")
            #expect(ScheduleText.days([1,7])=="주말")
            #expect(ScheduleText.days([2,4,6])=="월·수·금")
            #expect(ScheduleText.days([1,2])=="월·일")
            #expect(ScheduleText.action(.topUp)=="한 번 완충")
            #expect(ScheduleText.action(.clearLimit)=="상한 끄기")
            #expect(ScheduleText.sentence(Self.rule([7],7,5,.topUp))=="토 07:05 · 한 번 완충")
        }
    }
    @Test func preferencesDropBadRulesKeepOthers() throws {
        try AppLanguage.$forced.withValue(.ko) { () throws in
            var p=UserPreferences();p.schedules=[Self.rule([],22),Self.rule(22),Self.rule(23,0,.setLimit(73))]
            var json=String(data:try JSONEncoder().encode(p),encoding:.utf8)!
            json=json.replacingOccurrences(of:"\"schedules\":[",with:"\"schedules\":[{\"x\":1},")
            var back=try JSONDecoder().decode(UserPreferences.self,from:Data(json.utf8))
            #expect(back.schedules.count==3)
            back.validate()
            #expect(back.schedules.count==1);#expect(back.schedules.first?.hour==22)
            var many=UserPreferences();many.schedules=(0..<12).map { Self.rule($0) };many.validate()
            #expect(many.schedules.count==SchedulePolicy.maxRules)
            let empty=try JSONDecoder().decode(UserPreferences.self,from:Data("{}".utf8));#expect(empty.schedules.isEmpty)
        }
    }
    @Test func whenReadsRelativeDay() {
        AppLanguage.$forced.withValue(.ko) {
            let now=Self.at(10,22,21,0)
            #expect(ScheduleText.when(Self.at(10,22,22,0),now:now,calendar:cal)=="오늘 22:00")
            #expect(ScheduleText.when(Self.at(10,23,7,5),now:now,calendar:cal)=="내일 07:05")
            #expect(ScheduleText.when(Self.at(10,26,0,0),now:now,calendar:cal)=="10월 26일 00:00")
        }
    }
    @Test func dstFallBackRunsOnce() {
        AppLanguage.$forced.withValue(.ko) {
            // 01:30 happens twice in New York on 2026-11-01; checks every 30 s must run it once.
            let ny=Self.calendar("America/New_York"),r=Self.rule(1,30)
            var t=ny.date(from:DateComponents(year:2026,month:11,day:1,hour:0))!,last=t,runs=0
            let end=t+4*3600
            while t<end { t+=30;if case .run=SchedulePolicy.due([r],lastCheck:last,now:t,calendar:ny) { runs+=1 };last=t }
            #expect(runs==1)
        }
    }
    @Test func templateNamesCountAsAutomatic() {
        AppLanguage.$forced.withValue(.ko) {
            var r=ChargeScheduleRule.templates(now:Self.at(10,22,12,0))[0]
            #expect(ScheduleText.isAutoName(r.name,for:r))
            r.action = .setLimit(80)
            #expect(ScheduleText.isAutoName(r.name,for:r))
            #expect(ScheduleText.isAutoName(ScheduleText.sentence(r),for:r))
            #expect(ScheduleText.isAutoName("",for:r))
            #expect(!ScheduleText.isAutoName("출장 전날",for:r))
        }
    }
    @Test func templatesAreValid() {
        AppLanguage.$forced.withValue(.ko) {
            let t=ChargeScheduleRule.templates(now:Self.at(10,22,12,0))
            #expect(t.map(\.name)==["밤에는 70%","평일 아침 완충","주말엔 80%"])
            #expect(t.allSatisfy { $0.isValid })
            #expect(t[1].weekdays==Set(2...6) && t[1].action == .topUp && t[1].hour==7)
            #expect(t[2].weekdays==[1,7] && t[2].action == .setLimit(80))
        }
    }
}
