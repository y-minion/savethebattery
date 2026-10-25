import Testing
import Foundation
@testable import BatteryCore

struct PowerFlowTests {
    @Test func chargingSplitsInput() {
        var b=BatterySnapshot();b.onAC=true;b.charging=true;b.watts=14
        b.power=PowerReading(adapterName:"70W USB-C Power Adapter",adapterWatts:70,inputW:32,systemW:18)
        let s=PowerSummary.make(b)!
        #expect(s.headline=="충전기에서 32 W 들어옴");#expect(s.adapter=="70W USB-C")
        #expect(s.segments==[.adapterToMac(18),.adapterToBattery(14)])
        #expect(s.segments.map(\.label)==["맥 18 W","배터리 +14 W"])
    }
    @Test func pausedIsAdapterOnly() {
        var b=BatterySnapshot();b.onAC=true;b.watts=0.2
        b.power=PowerReading(inputW:8.8)
        let s=PowerSummary.make(b)!
        #expect(s.segments==[.adapterToMac(8.8)]);#expect(s.headline=="충전기에서 9 W 들어옴")
    }
    @Test func pluggedDischargeShowsBoth() {
        var b=BatterySnapshot();b.onAC=true;b.watts = -5
        b.power=PowerReading(inputW:20)
        let s=PowerSummary.make(b)!
        #expect(s.segments==[.adapterToMac(20),.batteryToMac(5)])
        #expect(s.headline=="충전기 20 W + 배터리 5 W 사용")
        #expect(s.segments.last?.label=="배터리에서 5 W")
    }
    @Test func onBatteryIgnoresAdapterKeys() {
        var b=BatterySnapshot();b.onAC=false;b.watts = -7
        b.power=PowerReading(adapterName:"x",adapterWatts:70,inputW:0)
        let s=PowerSummary.make(b)!
        #expect(s.segments==[.batteryToMac(7)]);#expect(s.headline=="배터리에서 7 W 사용")
    }
    @Test func missingKeysGiveNil() {
        var b=BatterySnapshot();b.onAC=true;b.watts=3
        #expect(PowerSummary.make(b)==nil)
        b.power=PowerReading()
        #expect(PowerSummary.make(b)==nil)
        var c=BatterySnapshot();c.onAC=false
        #expect(PowerSummary.make(c)==nil)
    }
    @Test func adapterStringVariants() {
        var b=BatterySnapshot();b.onAC=true;b.watts=1
        b.power=PowerReading(adapterName:nil,adapterWatts:70,inputW:5)
        #expect(PowerSummary.make(b)!.adapter=="70W")
        b.power=PowerReading(adapterName:"x",adapterWatts:nil,inputW:5)
        #expect(PowerSummary.make(b)!.adapter==nil)
    }
    @Test func hardwarePercentFromRawCapacity() {
        func pct(_ r:Int,_ f:Int)->Int?{BatterySnapshot.decode(["BatteryData":["RemainingCapacity":r,"FullChargeCapacity":f]]).hardwarePercent}
        #expect(pct(3569,5332)==67)
        #expect(pct(3569,0)==nil)
        #expect(pct(5340,5332)==100)
        #expect(pct(5400,5332)==nil)
        #expect(pct(5500,5332)==nil)
    }
    @Test func decodeReadsTelemetry() {
        let b=BatterySnapshot.decode(["PowerTelemetryData":["SystemPowerIn":8754,"SystemLoad":8754],"AdapterDetails":["Watts":70,"Name":"70W USB-C Power Adapter "]])
        #expect(b.power?.inputW==8.754);#expect(b.power?.systemW==8.754);#expect(b.power?.adapterWatts==70)
        #expect(b.power?.adapterName=="70W USB-C Power Adapter")
    }
}
