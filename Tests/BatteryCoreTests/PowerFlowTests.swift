import Testing
import Foundation
@testable import BatteryCore

struct PowerFlowTests {
    @Test func chargingSplitsInput() {
        AppLanguage.$forced.withValue(.ko) {
            var b=BatterySnapshot();b.onAC=true;b.charging=true;b.watts=14
            b.power=PowerReading(adapterName:"70W USB-C Power Adapter",adapterWatts:70,inputW:32,systemW:18)
            let s=PowerSummary.make(b)!
            #expect(s.headline=="충전기에서 32 W 들어옴");#expect(s.adapter=="70W USB-C")
            #expect(s.segments==[.adapterToMac(18),.adapterToBattery(14)])
            #expect(s.segments.map(\.label)==["맥 18 W","배터리 +14 W"])
        }
    }
    @Test func pausedIsAdapterOnly() {
        AppLanguage.$forced.withValue(.ko) {
            var b=BatterySnapshot();b.onAC=true;b.watts=0.2
            b.power=PowerReading(inputW:8.8)
            let s=PowerSummary.make(b)!
            #expect(s.segments==[.adapterToMac(8.8)]);#expect(s.headline=="충전기에서 9 W 들어옴")
        }
    }
    @Test func pluggedDischargeShowsBoth() {
        AppLanguage.$forced.withValue(.ko) {
            var b=BatterySnapshot();b.onAC=true;b.watts = -5
            b.power=PowerReading(inputW:20)
            let s=PowerSummary.make(b)!
            #expect(s.segments==[.adapterToMac(20),.batteryToMac(5)])
            #expect(s.headline=="충전기 20 W + 배터리 5 W 사용")
            #expect(s.segments.last?.label=="배터리에서 5 W")
        }
    }
    @Test func aboveTheLimitExplainsTheBatteryUse() {
        AppLanguage.$forced.withValue(.ko) {
            var b=BatterySnapshot();b.onAC=true;b.percent=76;b.watts = -10
            b.power=PowerReading(adapterWatts:68,inputW:0.3)
            let s=PowerSummary.make(b,limit:70)!
            #expect(s.headline=="충전기 연결됨 · 배터리에서 10 W 사용")
            #expect(s.segments==[.batteryToMac(10)])
            #expect(s.note=="배터리가 상한 70%보다 높아 충전기 대신 배터리를 씁니다. 70%가 되면 충전기 전원으로 돌아갑니다.")
            b.power=PowerReading(inputW:0)
            #expect(PowerSummary.make(b,limit:70)?.segments==[.batteryToMac(10)])
        }
    }
    @Test func noNoteAtOrBelowTheLimitOrWithoutOne() {
        AppLanguage.$forced.withValue(.ko) {
            var b=BatterySnapshot();b.onAC=true;b.percent=70;b.watts = -5
            b.power=PowerReading(inputW:20)
            #expect(PowerSummary.make(b,limit:70)?.note==nil)
            b.percent=76
            #expect(PowerSummary.make(b)?.note==nil)
            b.watts=0.1
            #expect(PowerSummary.make(b,limit:70)?.note==nil)
            var c=BatterySnapshot();c.onAC=true;c.percent=76;c.watts=0.1;c.power=PowerReading(inputW:0)
            #expect(PowerSummary.make(c,limit:70)==nil)
        }
    }
    @Test func diagramValues() {
        AppLanguage.$forced.withValue(.ko) {
            func make(_ ac:Bool,_ watts:Double,_ input:Double?,percent:Int=50,limit:Int?=nil) -> PowerSummary? {
                var b=BatterySnapshot();b.onAC=ac;b.watts=watts;b.percent=percent;b.power=PowerReading(inputW:input);return PowerSummary.make(b,limit:limit)
            }
            let charging=make(true,14,32)!
            #expect(charging.chargerW==32);#expect(charging.macW==18);#expect(charging.battery == .charging(14))
            let holding=make(true,0.2,20)!
            #expect(holding.chargerW==20);#expect(holding.macW==20);#expect(holding.battery == .idle)
            let both=make(true,-5,20)!
            #expect(both.chargerW==20);#expect(both.macW==25);#expect(both.battery == .discharging(5))
            let above=make(true,-10,0.3,percent:76,limit:70)!
            #expect(above.chargerW==0);#expect(above.macW==10);#expect(above.battery == .discharging(10))
            let unplugged=make(false,-7,nil)!
            #expect(unplugged.chargerW==nil);#expect(unplugged.macW==7);#expect(unplugged.battery == .discharging(7))
        }
    }
    @Test func onBatteryIgnoresAdapterKeys() {
        AppLanguage.$forced.withValue(.ko) {
            var b=BatterySnapshot();b.onAC=false;b.watts = -7
            b.power=PowerReading(adapterName:"x",adapterWatts:70,inputW:0)
            let s=PowerSummary.make(b)!
            #expect(s.segments==[.batteryToMac(7)]);#expect(s.headline=="배터리에서 7 W 사용")
        }
    }
    @Test func missingKeysGiveNil() {
        AppLanguage.$forced.withValue(.ko) {
            var b=BatterySnapshot();b.onAC=true;b.watts=3
            #expect(PowerSummary.make(b)==nil)
            b.power=PowerReading()
            #expect(PowerSummary.make(b)==nil)
            var c=BatterySnapshot();c.onAC=false
            #expect(PowerSummary.make(c)==nil)
        }
    }
    @Test func adapterStringVariants() {
        AppLanguage.$forced.withValue(.ko) {
            var b=BatterySnapshot();b.onAC=true;b.watts=1
            b.power=PowerReading(adapterName:nil,adapterWatts:70,inputW:5)
            #expect(PowerSummary.make(b)!.adapter=="70W")
            b.power=PowerReading(adapterName:"x",adapterWatts:nil,inputW:5)
            #expect(PowerSummary.make(b)!.adapter==nil)
        }
    }
    @Test func hardwarePercentFromRawCapacity() {
        AppLanguage.$forced.withValue(.ko) {
            func pct(_ r:Int,_ f:Int)->Int?{BatterySnapshot.decode(["BatteryData":["RemainingCapacity":r,"FullChargeCapacity":f]]).hardwarePercent}
            #expect(pct(3569,5332)==67)
            #expect(pct(3569,0)==nil)
            #expect(pct(5340,5332)==100)
            #expect(pct(5400,5332)==nil)
            #expect(pct(5500,5332)==nil)
        }
    }
    @Test func decodeReadsTelemetry() {
        AppLanguage.$forced.withValue(.ko) {
            let b=BatterySnapshot.decode(["PowerTelemetryData":["SystemPowerIn":8754,"SystemLoad":8754],"AdapterDetails":["Watts":70,"Name":"70W USB-C Power Adapter "]])
            #expect(b.power?.inputW==8.754);#expect(b.power?.systemW==8.754);#expect(b.power?.adapterWatts==70)
            #expect(b.power?.adapterName=="70W USB-C Power Adapter")
        }
    }
}
