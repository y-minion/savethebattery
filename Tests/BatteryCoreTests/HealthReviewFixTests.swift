import Testing
import Foundation
@testable import BatteryCore
@testable import BatteryPlatform
struct HealthReviewFixTests {
    let c:Calendar={ var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:"UTC")!;return c }()
    let t0=Date(timeIntervalSince1970:1_790_000_000)
    func snap(_ t:Date,ac:Bool=true,temp:Double=36,id:String?=nil) -> BatterySnapshot { var s=BatterySnapshot();s.timestamp=t;s.percent=60;s.temperature=temp;s.onAC=ac;s.healthPrecise=90;s.batteryID=id;return s }
    func dir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("vb-fix-\(UUID().uuidString)") }
    @Test func olderFilesWithMissingKeysStillLoad() throws {
        let d=try JSONDecoder().decode(DailyUsage.self,from:Data(#"{"day":0,"observed":30}"#.utf8))
        #expect(d.observed==30);#expect(d.hot35OnAC==0)
        let f=try JSONDecoder().decode(HealthFile.self,from:Data(#"{"days":[{"day":0}]}"#.utf8))
        #expect(f.days.count==1);#expect(f.version==1)
    }
    @Test func repeatedCorruptionKeepsEveryCopy() throws {
        let d=dir();try FileManager.default.createDirectory(at:d,withIntermediateDirectories:true)
        let url=d.appendingPathComponent("health.json")
        try Data("{a".utf8).write(to:url);_=HealthStore(url:url).read()
        try Data("{b".utf8).write(to:url);_=HealthStore(url:url).read()
        #expect(try FileManager.default.contentsOfDirectory(atPath:d.path).filter { $0.hasPrefix("health.json.corrupt") }.count==2)
    }
    @Test func readOnlyLoadLeavesUnreadableFile() throws {
        let d=dir();try FileManager.default.createDirectory(at:d,withIntermediateDirectories:true)
        let url=d.appendingPathComponent("health.json");try Data("{a".utf8).write(to:url)
        #expect(HealthStore(url:url).read(repair:false).days.isEmpty)
        #expect(FileManager.default.fileExists(atPath:url.path))
        try Data("[{x".utf8).write(to:d.appendingPathComponent("sleep.json"))
        #expect(SleepStore(url:d.appendingPathComponent("sleep.json")).read(repair:false).isEmpty)
        #expect(FileManager.default.fileExists(atPath:d.appendingPathComponent("sleep.json").path))
    }
    @Test func statusExplainsWhatIsMissingAfterThirtyDays() {
        func days(_ v:[(Int,Double)]) -> [DailyUsage] { v.map { var d=DailyUsage(day:c.date(byAdding:.day,value:$0.0,to:t0)!);d.health=$0.1;return d } }
        let small=HealthTrend.make(days([(0,95),(10,94.8),(20,94.9),(30,94.6),(40,94.7)]),now:t0,calendar:c)
        #expect(HealthText.trend(small,calendar:c)=="변화가 작아 아직 추세 계산 불가 (변화 0.4/1.0%p)")
        let few=HealthTrend.make(days([(0,95),(40,93)]),now:t0,calendar:c)
        #expect(HealthText.trend(few,calendar:c)=="데이터 수집 중 (측정한 날 2/5일)")
        #expect(HealthText.trend(HealthTrend.make(days([(0,95),(3,94)]),now:t0,calendar:c),calendar:c)=="데이터 수집 중 (3/30일)")
    }
    @Test func roundingAloneDoesNotFlagSleep() {
        func e(_ h:Double,_ a:Int,_ b:Int) -> SleepEvent { var x=BatterySnapshot();x.timestamp=t0;x.percent=a;var y=BatterySnapshot();y.timestamp=t0.addingTimeInterval(h*3600);y.percent=b;return SleepEvent(before:x,after:y) }
        #expect(!e(1.1,80,78).isHigh);#expect(!e(2,80,77).isHigh);#expect(e(2,80,76).isHigh)
        #expect(HealthAdvisor.suggestions(week:UsageSummary.make([]),sleeps:[e(1.1,80,78)],context:AdvisorContext(limit:80,heatEnabled:true)).isEmpty)
    }
    @Test func heatSuggestionCountsOnlyAdapterHeat() {
        let onBattery=HealthLedger.record(snap(t0.addingTimeInterval(30)),after:snap(t0,ac:false),into:[],calendar:c)[0]
        #expect(onBattery.hot35==30);#expect(onBattery.hot35OnAC==0)
        let plugged=HealthLedger.record(snap(t0.addingTimeInterval(30)),after:snap(t0),into:[],calendar:c)[0]
        #expect(plugged.hot35OnAC==30)
        var hotBattery=DailyUsage(day:t0);hotBattery.hot35=3*3600
        #expect(HealthAdvisor.suggestions(week:UsageSummary.make([hotBattery]),sleeps:[],context:AdvisorContext(limit:80,heatEnabled:false)).isEmpty)
        var hotPlugged=hotBattery;hotPlugged.hot35OnAC=2*3600
        #expect(HealthAdvisor.suggestions(week:UsageSummary.make([hotPlugged]),sleeps:[],context:AdvisorContext(limit:80,heatEnabled:false)).map(\.kind)==[.heatHold])
    }
    @Test func forwardClockJumpDoesNotDeleteHistory() {
        var days:[DailyUsage]=(0..<30).map { DailyUsage(day:c.date(byAdding:.day,value:$0,to:c.startOfDay(for:t0))!) }
        let today=c.date(byAdding:.day,value:29,to:t0)!
        let future=c.date(byAdding:.year,value:2,to:today)!
        days=HealthLedger.record(snap(future),after:snap(today),into:days,calendar:c)
        #expect(days.count==31)
        days=HealthLedger.record(snap(today.addingTimeInterval(30)),after:snap(future),into:days,calendar:c)
        #expect(days.count==30);#expect(days.last!.day==c.startOfDay(for:today))
    }
    @Test func trendCacheReusesUnchangedInputs() {
        var cache=TrendCache()
        var d=DailyUsage(day:t0);d.health=90
        _=cache.trend(for:[d],now:t0,calendar:c);_=cache.trend(for:[d],now:t0.addingTimeInterval(60),calendar:c)
        #expect(cache.computations==1)
        d.health=89.9;_=cache.trend(for:[d],now:t0,calendar:c)
        #expect(cache.computations==2)
        _=cache.trend(for:[d],now:t0.addingTimeInterval(86400),calendar:c)
        #expect(cache.computations==3)
    }
    @Test func snapshotJSONOmitsBatteryIdentity() throws {
        var s=BatterySnapshot();s.batteryID="abcdef0123456789"
        let json=String(data:try JSONEncoder().encode(s),encoding:.utf8)!
        #expect(!json.contains("batteryID"))
    }
}
