import Testing
import Foundation
import BatteryCore
struct HelperPolicyTests {
    let app="/Applications/Save the Battery.app/Contents/MacOS/Save the Battery"
    @Test func onlyConsoleUserRunningInstalledAppIsAllowed() {
        #expect(HelperPolicy.allows(clientUID:501,consoleUID:501,clientPath:app))
        #expect(!HelperPolicy.allows(clientUID:502,consoleUID:501,clientPath:app))
        #expect(!HelperPolicy.allows(clientUID:0,consoleUID:0,clientPath:app))
        #expect(!HelperPolicy.allows(clientUID:501,consoleUID:nil,clientPath:app))
        #expect(!HelperPolicy.allows(clientUID:501,consoleUID:501,clientPath:nil))
        #expect(!HelperPolicy.allows(clientUID:501,consoleUID:501,clientPath:"/tmp/Save the Battery.app/Contents/MacOS/Save the Battery"))
        #expect(!HelperPolicy.allows(clientUID:501,consoleUID:501,clientPath:"/Applications/Save the Battery.app/../Evil.app/x"))
        #expect(!HelperPolicy.allows(clientUID:501,consoleUID:501,clientPath:"/Applications/Save the Battery.appx/y"))
    }
    @Test func domainWritesAreBoundedAndKeepExistingFeatureState() {
        let fresh=TopoffDomain.writes(limit:79,existingFeature:nil)
        #expect((fresh?[TopoffDomain.limitKey] as? NSNumber)?.intValue==79)
        #expect((fresh?[TopoffDomain.featureKey] as? NSNumber)?.intValue==1)
        let kept=TopoffDomain.writes(limit:60,existingFeature:NSNumber(value:2))
        #expect(kept?.keys.sorted()==[TopoffDomain.limitKey])
        #expect(TopoffDomain.writes(limit:49,existingFeature:nil)==nil)
        #expect(TopoffDomain.writes(limit:101,existingFeature:nil)==nil)
    }
    /// Observed on the target: System Settings "off" stores MCLFeatureState = 0, "on" stores 1.
    @Test func lowLimitReEnablesTheObservedOffState() {
        let off=TopoffDomain.writes(limit:70,existingFeature:NSNumber(value:0))
        #expect((off?[TopoffDomain.featureKey] as? NSNumber)?.intValue==1)
        #expect((off?[TopoffDomain.limitKey] as? NSNumber)?.intValue==70)
        let on=TopoffDomain.writes(limit:70,existingFeature:NSNumber(value:1))
        #expect(on?.keys.sorted()==[TopoffDomain.limitKey])
        let text=TopoffDomain.writes(limit:70,existingFeature:"0" as NSString)
        #expect(text?.keys.sorted()==[TopoffDomain.limitKey])
    }
}
