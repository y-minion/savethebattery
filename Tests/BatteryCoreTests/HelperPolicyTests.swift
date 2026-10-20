import Testing
import Foundation
import BatteryCore
struct HelperPolicyTests {
    let app="/Applications/VibeBattery.app/Contents/MacOS/VibeBattery"
    @Test func onlyConsoleUserRunningInstalledAppIsAllowed() {
        #expect(HelperPolicy.allows(clientUID:501,consoleUID:501,clientPath:app))
        #expect(!HelperPolicy.allows(clientUID:502,consoleUID:501,clientPath:app))
        #expect(!HelperPolicy.allows(clientUID:0,consoleUID:0,clientPath:app))
        #expect(!HelperPolicy.allows(clientUID:501,consoleUID:nil,clientPath:app))
        #expect(!HelperPolicy.allows(clientUID:501,consoleUID:501,clientPath:nil))
        #expect(!HelperPolicy.allows(clientUID:501,consoleUID:501,clientPath:"/tmp/VibeBattery.app/Contents/MacOS/VibeBattery"))
        #expect(!HelperPolicy.allows(clientUID:501,consoleUID:501,clientPath:"/Applications/VibeBattery.app/../Evil.app/x"))
        #expect(!HelperPolicy.allows(clientUID:501,consoleUID:501,clientPath:"/Applications/VibeBattery.appx/y"))
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
}
