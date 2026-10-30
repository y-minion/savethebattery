import Testing
import Foundation
@testable import BatteryCore
struct FinalReviewTests {
    @Test func unsupportedReplyClearsDirtyAndStopsRetries() {
        AppLanguage.$forced.withValue(.ko) {
            let o=MagSafeLEDPolicy.outcome(reply:HelperReply.ledUnsupported.rawValue)
            #expect(o.clearDirty);#expect(o.unsupported)
            #expect(MagSafeLEDPolicy.write(target:.off,last:nil,dirty:false,unsupported:o.unsupported) == nil)
            #expect(MagSafeLEDPolicy.write(target:nil,last:nil,dirty:true,unsupported:o.unsupported) == nil)
        }
    }
    @Test func otherRepliesKeepDirtyAndRetry() {
        AppLanguage.$forced.withValue(.ko) {
            for r in [HelperReply.ledFailed.rawValue,HelperReply.noReply.rawValue] {
                let o=MagSafeLEDPolicy.outcome(reply:r);#expect(!o.clearDirty);#expect(!o.unsupported)
            }
            #expect(MagSafeLEDPolicy.write(target:.off,last:nil,dirty:true) == .off)
            #expect(!HelperReply.ledFailed.text.contains("("))
        }
    }
    @Test func acWithoutBatteryReadingHidesBar() {
        AppLanguage.$forced.withValue(.ko) {
            var b=BatterySnapshot();b.onAC=true;b.watts=nil
            b.power=PowerReading(adapterName:nil,adapterWatts:70,inputW:30)
            #expect(PowerSummary.make(b)==nil)
        }
    }
    @Test func hugeCapacitiesDoNotTrap() {
        AppLanguage.$forced.withValue(.ko) {
            let s=BatterySnapshot.decode(["BatteryData":["RemainingCapacity":1e300,"FullChargeCapacity":1e-300,"DesignCapacity":1e300,"NominalChargeCapacity":1e-300]])
            #expect(s.hardwarePercent==nil);#expect(s.designCapacity==nil)
            let n=BatterySnapshot.decode(["BatteryData":["RemainingCapacity":0,"FullChargeCapacity":5000]])
            #expect(n.hardwarePercent==0)
        }
    }
    @Test func highPowerCaption() {
        AppLanguage.$forced.withValue(.ko) {
            let high=LowPowerSettings.parse("Battery Power:\n powermode 2\nAC Power:\n powermode 2\n")
            #expect(!high.isConditional);#expect(high.isHighPower)
            #expect(LowPowerText.notes(high)==[LowPowerText.highPower])
            let mixed=LowPowerSettings.parse("Battery Power:\n powermode 1\nAC Power:\n powermode 2\n")
            #expect(LowPowerText.notes(mixed)==[LowPowerText.conditional,LowPowerText.highPower])
            let plain=LowPowerSettings.parse("Battery Power:\n powermode 0\nAC Power:\n powermode 0\n")
            #expect(LowPowerText.notes(plain).isEmpty)
            #expect(!LowPowerSettings.parse("Battery Power:\n lowpowermode 2\nAC Power:\n lowpowermode 2\n").isHighPower)
        }
    }
    @Test func unavailableHelperWording() {
        AppLanguage.$forced.withValue(.ko) {
            #expect(LowPowerText.unavailable(.outdated)==LowPowerText.needsUpdate)
            #expect(LowPowerText.unavailable(.notInstalled)=="헬퍼를 설치하면 여기서 바로 바꿀 수 있습니다")
            #expect(LowPowerText.unavailable(.unreachable).hasPrefix("헬퍼에 연결하지 못했습니다"))
            #expect(LowPowerText.unavailable(.wrongLocation).contains("/Applications"))
            #expect(LowPowerText.unavailable(.ready)==LowPowerText.failed)
            for s in [HelperStatus.notInstalled,.wrongLocation,.unreachable] { #expect(LowPowerText.unavailable(s) != LowPowerText.needsUpdate) }
        }
    }
}
