import Testing
import Foundation
@testable import BatteryCore
struct HealthReportTests {
    let c:Calendar={ var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:"UTC")!;return c }()
    let now=Date(timeIntervalSince1970:1_790_000_000)
    func snap(_ t:Date,_ p:Int,ac:Bool=false) -> BatterySnapshot { var s=BatterySnapshot();s.timestamp=t;s.percent=p;s.onAC=ac;return s }
    func event(hours:Double,from a:Int,to b:Int,ac:Bool=false) -> SleepEvent { SleepEvent(before:snap(now,a,ac:ac),after:snap(now.addingTimeInterval(hours*3600),b)) }
    func day(_ ago:Int,soc95:Double=0,hot35:Double=0,stress:Double=0,at80:Double=0) -> DailyUsage {
        var d=DailyUsage(day:c.date(byAdding:.day,value:-ago,to:c.startOfDay(for:now))!);d.observed=3600;d.soc95=soc95;d.hot35=hot35;d.hot35OnAC=hot35;d.stress=stress;d.stressAt80=at80;d.stressSeconds=stress>0 ? 100:0;return d
    }
    @Test func sleepDrainPerHour() {
        #expect(event(hours:8,from:80,to:76).drainPerHour==0.5)
        #expect(event(hours:2,from:80,to:76).isHigh)
        #expect(!event(hours:8,from:80,to:76).isHigh)
    }
    @Test func shortSleepHasNoDrain() { #expect(event(hours:0.9,from:80,to:79).drainPerHour==nil) }
    @Test func sleepOnAdapterOrGainHasNoDrain() {
        #expect(event(hours:8,from:80,to:70,ac:true).drainPerHour==nil)
        #expect(event(hours:8,from:70,to:80).drainPerHour==nil)
    }
    @Test func summaryAddsDaysAndComparesCap() {
        let s=UsageSummary.make([day(0,soc95:3600,stress:500,at80:350),day(1,soc95:1800,stress:500,at80:350)])
        #expect(s.days==2);#expect(s.observed==7200);#expect(s.soc95==5400);#expect(s.averageStress==5)
        #expect(abs((s.reductionAt80 ?? 0)-0.3)<1e-9)
        #expect(UsageSummary.make([day(0)]).reductionAt80==nil)
    }
    @Test func advisorThresholdsAndOrder() {
        let week=UsageSummary.make([day(0,soc95:6*3600,hot35:2*3600)])
        let all=HealthAdvisor.suggestions(week:week,sleeps:[event(hours:2,from:80,to:76)],context:AdvisorContext(limit:nil,heatEnabled:false))
        #expect(all.map(\.kind)==[.chargeLimit,.heatHold,.sleepDrain])
        let under=UsageSummary.make([day(0,soc95:6*3600-60,hot35:2*3600-60)])
        #expect(HealthAdvisor.suggestions(week:under,sleeps:[],context:AdvisorContext(limit:nil,heatEnabled:false)).isEmpty)
        #expect(HealthAdvisor.suggestions(week:week,sleeps:[],context:AdvisorContext(limit:80,heatEnabled:true)).isEmpty)
        #expect(HealthAdvisor.suggestions(week:week,sleeps:[],context:AdvisorContext(limit:85,heatEnabled:true)).map(\.kind)==[.chargeLimit])
    }
    @Test func advisorOnlyLooksAtFiveRecentSleeps() {
        let old=[event(hours:2,from:80,to:76)]+Array(repeating:event(hours:8,from:80,to:79),count:5)
        #expect(HealthAdvisor.suggestions(week:UsageSummary.make([]),sleeps:old,context:AdvisorContext(limit:80,heatEnabled:true)).isEmpty)
    }
    @Test func reportUsesWindowsAndCurrentBattery() {
        var b=BatterySnapshot();b.healthPrecise=88.5;b.cycles=300;b.designCycles=1000
        var replaced=day(10);replaced.batteryID="old";replaced.health=70
        var current=day(0,soc95:60);current.batteryID="new";current.health=88.5
        let r=HealthReport.make(snapshot:b,days:[replaced,day(8,soc95:999),current],sleeps:[event(hours:8,from:80,to:76),event(hours:9,from:80,to:70)],context:AdvisorContext(limit:80,heatEnabled:true),now:now,calendar:c)
        #expect(r.health==88.5);#expect(r.marginTo80==8.5);#expect(r.cycles==300);#expect(r.designCycles==1000)
        #expect(r.week.days==1);#expect(r.week.soc95==60);#expect(r.month.days==3)
        #expect(r.trend.status == .collecting(days:0,points:1,change:0))
        #expect(r.sleeps.first?.endPercent==70)
    }
    @Test func reportWithoutBatteryHasNoHealth() {
        let r=HealthReport.make(snapshot:BatterySnapshot(),days:[],sleeps:[],context:AdvisorContext(limit:nil,heatEnabled:false),now:now,calendar:c)
        #expect(r.health==nil);#expect(r.marginTo80==nil);#expect(HealthText.lines(r,calendar:c).first=="배터리 정보 없음")
    }
    @Test func textDescribesStatus() {
        #expect(HealthText.trend(HealthTrend(status:.collecting(days:12,points:9,change:0)),calendar:c)=="데이터 수집 중 (12/30일)")
        #expect(HealthText.trend(HealthTrend(status:.beyondHorizon),calendar:c)=="80% 도달 예상: 15년 이상")
        let e=c.date(from:DateComponents(year:2028,month:3,day:2))!
        #expect(HealthText.trend(HealthTrend(status:.projected(earliest:e,latest:nil)),calendar:c)=="80% 도달 예상: 2028년 3월 ~ 알 수 없음")
        #expect(HealthText.stress(UsageSummary.make([day(0,stress:500,at80:365)]))=="상한 80%였다면 스트레스 −27%")
        #expect(HealthText.stress(UsageSummary.make([day(0,stress:500,at80:499)]))=="이미 80% 이하로 유지 중")
        #expect(HealthText.stress(UsageSummary.make([]))=="측정 중")
    }
}
