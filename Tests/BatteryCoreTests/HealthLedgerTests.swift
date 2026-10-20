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
