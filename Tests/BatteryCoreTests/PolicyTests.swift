import Testing
import Foundation
@testable import BatteryCore
struct PolicyTests {
    @Test func testMissingSensorsStayUnknown() {
        let value = BatterySnapshot.decode(["CurrentCapacity": 62, "MaxCapacity":100])
        #expect(value.percent ==  62); #expect(value.health == nil); #expect(value.temperature == nil)
    }
    @Test func testRawCapacityIsNotHealthPercent() {
        let value = BatterySnapshot.decode(["CurrentCapacity":55,"MaxCapacity":100,"CycleCount":305,"BatteryData":["DesignCapacity":6000,"NominalChargeCapacity":5100]])
        #expect(value.health == 85); #expect(value.cycles == 305)
    }
    @Test func testSignedCurrentAndUnits() {
        let value = BatterySnapshot.decode(["Voltage":12000,"InstantAmperage":UInt64.max-999,"Temperature":3200])
        #expect(abs((value.watts ?? 0) - (-12)) < 0.01); #expect(value.temperature == 32)
    }
    @Test func testInvalidTemperatureAndChargeAreNotShown() {
        let value = BatterySnapshot.decode(["CurrentCapacity":999,"Temperature":0])
        #expect(value.percent == nil); #expect(value.temperature == nil)
    }
    @Test func testHysteresisDoesNotRepeatedlyRecharge() {
        var b = BatterySnapshot(); b.percent=78; b.onAC=true
        #expect(ChargePolicy.decide(snapshot:b,settings:.init(),previous:.hold) == .hold)
        #expect(ChargePolicy.decide(snapshot:b,settings:.init(),previous:.charge) == .charge)
        b.percent=80; #expect(ChargePolicy.decide(snapshot:b,settings:.init(),previous:.charge) == .hold)
        b.percent=74; #expect(ChargePolicy.decide(snapshot:b,settings:.init(),previous:.hold) == .charge)
    }
    @Test func testHeatAndStaleSensorFailClosed() {
        var b=BatterySnapshot(); b.percent=50; b.onAC=true; b.temperature=36
        var s=ChargeSettings(); s.heatProtection=true
        #expect(ChargePolicy.decide(snapshot:b,settings:s,previous:.charge) == .heatHold)
        b.temperature=34; #expect(ChargePolicy.decide(snapshot:b,settings:s,previous:.heatHold) == .heatHold)
        b.temperature=nil; #expect(ChargePolicy.decide(snapshot:b,settings:s,previous:.charge) == .unknown)
        b.timestamp=Date(timeIntervalSince1970:0)
        #expect(ChargePolicy.decide(snapshot:b,settings:s,previous:.charge) == .unknown)
    }
    @Test func testCleanupRequiresSuccessfulOwnedOptIn() {
        for outcome in [SessionOutcome.running,.failed,.cancelled,.detached,.expired] {
            #expect(!SessionPolicy.cleanupAllowed(outcome:outcome,registered:true,shared:false,policy:.safe))
        }
        #expect(!SessionPolicy.cleanupAllowed(outcome:.succeeded,registered:true,shared:false,policy:.observe))
        #expect(!SessionPolicy.cleanupAllowed(outcome:.succeeded,registered:false,shared:false,policy:.safe))
        #expect(!SessionPolicy.cleanupAllowed(outcome:.succeeded,registered:true,shared:true,policy:.safe))
        #expect(SessionPolicy.cleanupAllowed(outcome:.succeeded,registered:true,shared:false,policy:.safe))
    }
}
