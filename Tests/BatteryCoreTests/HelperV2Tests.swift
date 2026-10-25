import Testing
import Foundation
@testable import BatteryCore

struct HelperV2Tests {
    @Test func parsesPowermode() {
        let s=LowPowerSettings.parse("Battery Power:\n powermode            1\nAC Power:\n powermode            0\n")
        #expect(s.key=="powermode");#expect(s.battery==1);#expect(s.ac==0)
        #expect(s.isConditional)
        #expect(s.arguments(on:false)==["-a","powermode","0"])
    }
    @Test func parsesLegacyKey() {
        let s=LowPowerSettings.parse("Battery Power:\n lowpowermode         1\n sleep 1\nAC Power:\n lowpowermode         1\n")
        #expect(s.key=="lowpowermode");#expect(s.battery==1);#expect(s.ac==1)
        #expect(!s.isConditional)
        #expect(s.arguments(on:true)==["-a","lowpowermode","1"])
    }
    @Test func noKeyGivesNoArguments() {
        let s=LowPowerSettings.parse("Battery Power:\n sleep 1\nAC Power:\n sleep 0\n")
        #expect(s.key==nil);#expect(s.arguments(on:true)==nil)
    }
    @Test func ledAllowList() {
        #expect(MagSafeLED(rawValue:2)==nil)
        #expect(MagSafeLED.allCases.map(\.rawValue)==[0,1,3,4])
    }
    @Test func oldHelperIsOutdatedButCanSetLimit() {
        #expect(HelperStatus.evaluate(installed:true,appPath:"/Applications/VibeBattery.app",probe:{ true },version:{ nil }) == .outdated)
        #expect(HelperStatus.outdated.canSetLimit)
        #expect(!HelperStatus.unreachable.canSetLimit)
    }
    @Test func currentHelperIsReady() {
        #expect(HelperPolicy.protocolVersion==2)
        #expect(HelperStatus.evaluate(installed:true,appPath:"/Applications/VibeBattery.app",probe:{ true },version:{ 2 }) == .ready)
        #expect(HelperStatus.ready.canSetLimit)
    }
}
