import Testing
import Foundation
@testable import BatteryCore
struct SnapshotHealthTests {
    @Test func decodesPreciseHealthDesignAndHashedSerial() {
        let s=BatterySnapshot.decode(["CycleCount":12,"DesignCycleCount9C":1000,"Serial":"TESTSERIAL","BatteryData":["DesignCapacity":5000,"NominalChargeCapacity":4512]])
        #expect(s.healthPrecise==90.2);#expect(s.health==90)
        #expect(s.designCapacity==5000);#expect(s.designCycles==1000)
        #expect(s.batteryID?.count==16);#expect(s.batteryID != nil && !s.batteryID!.contains("TEST"))
        #expect(BatterySnapshot.decode(["Serial":"TESTSERIAL"]).batteryID==s.batteryID)
    }
    @Test func legacyHistorySampleStillDecodes() throws {
        let old=#"{"timestamp":0,"percent":50,"health":88,"cycles":10,"onAC":true,"charging":false}"#
        let s=try JSONDecoder().decode(BatterySnapshot.self,from:Data(old.utf8))
        #expect(s.percent==50);#expect(s.healthPrecise==nil);#expect(s.batteryID==nil)
    }
}
func seoul() -> Calendar { var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:"Asia/Seoul")!;return c }
func sample(_ t:Date,percent:Int?=96,temp:Double?=36,ac:Bool=true,health:Double?=90,cycles:Int?=10,design:Int?=5000,id:String?="a") -> BatterySnapshot {
    var s=BatterySnapshot();s.timestamp=t;s.percent=percent;s.temperature=temp;s.onAC=ac;s.healthPrecise=health;s.cycles=cycles;s.designCapacity=design;s.batteryID=id;return s
}
func at(_ y:Int,_ m:Int,_ d:Int,_ h:Int=12,_ min:Int=0,_ sec:Int=0) -> Date { seoul().date(from:DateComponents(year:y,month:m,day:d,hour:h,minute:min,second:sec))! }
struct HealthLedgerTests {
    @Test func accumulatesIntervalWithPreviousState() {
        let c=seoul(),a=sample(at(2026,10,20)),b=sample(at(2026,10,20,12,0,30),percent:50,temp:20,ac:false,health:89.9)
        let days=HealthLedger.record(b,after:a,into:[],calendar:c)
        #expect(days.count==1);let d=days[0]
        #expect(d.day==c.startOfDay(for:a.timestamp))
        #expect(d.observed==30);#expect(d.onAC==30);#expect(d.soc90==30);#expect(d.soc95==30);#expect(d.hot35==30);#expect(d.hot40==0)
        #expect(d.averageSoC==96);#expect(d.maxTemperature==36);#expect(d.stressSeconds==30)
        #expect(abs(d.stress-StressModel.rate(soc:96,temperature:36)*30)<1e-9)
        #expect(abs(d.stressAt80-StressModel.rate(soc:80,temperature:36)*30)<1e-9)
        #expect(d.health==89.9);#expect(d.cycles==10);#expect(d.designCapacity==5000);#expect(d.batteryID=="a")
    }
    @Test func longGapIsUnknownButDayValuesUpdate() {
        let days=HealthLedger.record(sample(at(2026,10,20,12,10)),after:sample(at(2026,10,20)),into:[],calendar:seoul())
        #expect(days.count==1);#expect(days[0].observed==0);#expect(days[0].health==90)
    }
    @Test func splitsAtLocalMidnight() {
        let days=HealthLedger.record(sample(at(2026,10,21,0,0,20)),after:sample(at(2026,10,20,23,59,50)),into:[],calendar:seoul())
        #expect(days.count==2);#expect(days[0].observed==10);#expect(days[1].observed==20)
    }
    @Test func clockGoingBackwardsDropsInterval() {
        let first=HealthLedger.record(sample(at(2026,10,20,12,0,30)),after:sample(at(2026,10,20)),into:[],calendar:seoul())
        let after=HealthLedger.record(sample(at(2026,10,20,11),health:50),after:sample(at(2026,10,20,12,0,30)),into:first,calendar:seoul())
        #expect(after==first)
    }
    @Test func missingSensorsSkipTheirTotals() {
        let d=HealthLedger.record(sample(at(2026,10,20,12,0,30)),after:sample(at(2026,10,20),temp:nil),into:[],calendar:seoul())[0]
        #expect(d.observed==30);#expect(d.soc95==30);#expect(d.hot35==0);#expect(d.stressSeconds==0);#expect(d.maxTemperature==nil)
        let e=HealthLedger.record(sample(at(2026,10,20,12,0,30)),after:sample(at(2026,10,20),percent:nil),into:[],calendar:seoul())[0]
        #expect(e.socSeconds==0);#expect(e.hot35==30);#expect(e.stressSeconds==0)
    }
    @Test func missingValuesKeepEarlierDayValues() {
        let first=HealthLedger.record(sample(at(2026,10,20)),after:nil,into:[],calendar:seoul())
        let d=HealthLedger.record(sample(at(2026,10,20,13),health:nil,cycles:nil,id:nil),after:nil,into:first,calendar:seoul())[0]
        #expect(d.health==90);#expect(d.cycles==10);#expect(d.batteryID=="a")
    }
    @Test func keepsFourHundredDays() {
        let c=seoul();var days:[DailyUsage]=[]
        for i in 0..<401 { days.append(DailyUsage(day:c.date(byAdding:.day,value:-i-1,to:c.startOfDay(for:at(2026,10,20)))!)) }
        days.sort { $0.day<$1.day }
        let out=HealthLedger.record(sample(at(2026,10,20)),after:nil,into:days,calendar:c)
        #expect(out.count==401);#expect(out.first!.day==c.date(byAdding:.day,value:-400,to:c.startOfDay(for:at(2026,10,20)))!)
    }
    @Test func segmentStartsAtBatteryReplacement() {
        func day(_ n:Int,id:String?,design:Int?,cycles:Int?) -> DailyUsage { var d=DailyUsage(day:Date(timeIntervalSince1970:Double(n)*86400));d.batteryID=id;d.designCapacity=design;d.cycles=cycles;return d }
        let swapped=[day(0,id:"a",design:5000,cycles:300),day(1,id:"b",design:5000,cycles:1),day(2,id:nil,design:nil,cycles:2)]
        #expect(BatterySegment.current(swapped).map(\.cycles)==[1,2])
        let resized=[day(0,id:nil,design:5000,cycles:3),day(1,id:nil,design:6000,cycles:4)]
        #expect(BatterySegment.current(resized).count==1)
        let reset=[day(0,id:nil,design:nil,cycles:300),day(1,id:nil,design:nil,cycles:2)]
        #expect(BatterySegment.current(reset).count==1)
        let same=[day(0,id:"a",design:5000,cycles:3),day(1,id:nil,design:nil,cycles:nil),day(2,id:"a",design:5000,cycles:4)]
        #expect(BatterySegment.current(same).count==3)
        #expect(BatterySegment.current([]).isEmpty)
    }
}
