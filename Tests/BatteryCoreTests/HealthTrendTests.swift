import Testing
import Foundation
@testable import BatteryCore
struct HealthTrendTests {
    let c:Calendar={ var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:"UTC")!;return c }()
    let start=Date(timeIntervalSince1970:1_790_000_000)
    func days(_ values:[(Int,Double)],cycles:((Int)->Int?)={ _ in nil }) -> [DailyUsage] {
        values.map { (n,h) in var d=DailyUsage(day:c.date(byAdding:.day,value:n,to:c.startOfDay(for:start))!);d.health=h;d.cycles=cycles(n);return d }
    }
    var now:Date { c.date(byAdding:.day,value:60,to:start)! }
    @Test func collectsUntilThirtyDaysFivePointsAndOnePoint() {
        #expect(HealthTrend.make(days([(0,95),(10,94),(20,93),(25,92.5),(29,92)]),now:now,calendar:c).status == .collecting(days:29,points:5))
        #expect(HealthTrend.make(days([(0,95),(40,94)]),now:now,calendar:c).status == .collecting(days:40,points:2))
        #expect(HealthTrend.make(days([(0,95),(10,94.8),(20,94.9),(30,94.5),(40,94.6)]),now:now,calendar:c).status == .collecting(days:40,points:5))
        #expect(HealthTrend.make([],now:now,calendar:c).status == .collecting(days:0,points:0))
    }
    @Test func linearDeclineProjectsExactDate() {
        let t=HealthTrend.make(days(stride(from:0,through:60,by:5).map { ($0,95-0.02*Double($0)) }),now:now,calendar:c)
        let expected=c.date(byAdding:.day,value:750,to:c.startOfDay(for:start))!
        #expect(t.status == .projected(earliest:expected,latest:expected))
    }
    @Test func outlierBarelyMovesProjection() {
        var v=stride(from:0,through:60,by:5).map { ($0,95-0.02*Double($0)) };v[6].1=60
        guard case .projected(let e,let l)=HealthTrend.make(days(v),now:now,calendar:c).status, let l else { Issue.record("no projection");return }
        let expected=c.date(byAdding:.day,value:750,to:c.startOfDay(for:start))!
        #expect(abs(e.timeIntervalSince(expected))<120*86400);#expect(abs(l.timeIntervalSince(expected))<120*86400);#expect(e<=l)
    }
    @Test func risingOrFlatIsNotDeclining() {
        #expect(HealthTrend.make(days([(0,90),(10,91),(20,90.5),(30,91.5),(40,92)]),now:now,calendar:c).status == .notDeclining)
    }
    @Test func belowThresholdIsReportedFirst() {
        #expect(HealthTrend.make(days([(0,79.5)]),now:now,calendar:c).status == .alreadyBelow)
    }
    @Test func nearlyFlatDeclineIsBeyondHorizon() {
        let t=HealthTrend.make(days(stride(from:0,through:400,by:20).map { ($0,95-Double($0)/400) }),now:now,calendar:c)
        #expect(t.status == .beyondHorizon)
        _=HealthTrend.make(days([(0,95),(10,95-1e-12),(20,94),(30,95),(40,95-2e-12),(50,95)]),now:now,calendar:c)
    }
    @Test func cycleProjectionNeedsSpreadAndOrders() {
        let v=stride(from:0,through:60,by:5).map { ($0,95-0.02*Double($0)) }
        let t=HealthTrend.make(days(v,cycles:{ 100+$0/2 }),now:now,calendar:c)
        #expect(t.cycles != nil);if let p=t.cycles { #expect(p.low<=(p.high ?? Int.max));#expect(p.low>=130) }
        #expect(HealthTrend.make(days(v,cycles:{ 100+$0/20 }),now:now,calendar:c).cycles==nil)
    }
}
