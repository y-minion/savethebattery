import Testing
import Foundation
@testable import BatteryCore

struct HelperV2Tests {
    @Test func parsesPowermode() {
        AppLanguage.$forced.withValue(.ko) {
            let s=LowPowerSettings.parse("Battery Power:\n powermode            1\nAC Power:\n powermode            0\n")
            #expect(s.key=="powermode");#expect(s.battery==1);#expect(s.ac==0)
            #expect(s.isConditional)
            #expect(s.arguments(on:false)==["-a","powermode","0"])
        }
    }
    @Test func parsesLegacyKey() {
        AppLanguage.$forced.withValue(.ko) {
            let s=LowPowerSettings.parse("Battery Power:\n lowpowermode         1\n sleep 1\nAC Power:\n lowpowermode         1\n")
            #expect(s.key=="lowpowermode");#expect(s.battery==1);#expect(s.ac==1)
            #expect(!s.isConditional)
            #expect(s.arguments(on:true)==["-a","lowpowermode","1"])
        }
    }
    @Test func noKeyGivesNoArguments() {
        AppLanguage.$forced.withValue(.ko) {
            let s=LowPowerSettings.parse("Battery Power:\n sleep 1\nAC Power:\n sleep 0\n")
            #expect(s.key==nil);#expect(s.arguments(on:true)==nil)
        }
    }
    @Test func ledAllowList() {
        AppLanguage.$forced.withValue(.ko) {
            #expect(MagSafeLED(rawValue:2)==nil)
            #expect(MagSafeLED.allCases.map(\.rawValue)==[0,1,3,4])
        }
    }
    @Test func oldHelperIsOutdatedButCanSetLimit() {
        AppLanguage.$forced.withValue(.ko) {
            #expect(HelperStatus.evaluate(installed:true,appPath:"/Applications/VibeBattery.app",probe:{ true },version:{ nil }) == .outdated)
            #expect(HelperStatus.outdated.canSetLimit)
            #expect(!HelperStatus.unreachable.canSetLimit)
        }
    }
    @Test func currentHelperIsReady() {
        AppLanguage.$forced.withValue(.ko) {
            #expect(HelperPolicy.protocolVersion==2)
            #expect(HelperStatus.evaluate(installed:true,appPath:"/Applications/VibeBattery.app",probe:{ true },version:{ 2 }) == .ready)
            #expect(HelperStatus.ready.canSetLimit)
        }
    }
}

struct LowPowerTextTests {
    @Test func captionFollowsHelperStatus() {
        AppLanguage.$forced.withValue(.ko) {
            #expect(LowPowerText.caption(.ready)==nil)
            #expect(LowPowerText.caption(.outdated)=="헬퍼 업데이트가 필요합니다")
            for s in [HelperStatus.notInstalled,.wrongLocation,.unreachable] { #expect(LowPowerText.caption(s)=="헬퍼를 설치하면 여기서 바로 바꿀 수 있습니다") }
        }
    }
    @Test func doneText() {
        AppLanguage.$forced.withValue(.ko) {
            #expect(LowPowerText.done(true)=="저전력 모드를 켰습니다.");#expect(LowPowerText.done(false)=="저전력 모드를 껐습니다.")
        }
    }
}
