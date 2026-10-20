import Testing
import Foundation
import BatteryCore
struct PreferencesTests {
    @Test func corruptPreferencesHaveBoundedLease() {
        var p=UserPreferences();p.hours = .infinity;p.validate();#expect(p.hours==4)
        p.hours = -1;p.validate();#expect(p.hours==4)
        p.hours=8;p.validate();#expect(p.hours==8)
    }
    @Test func shellQuotingPreservesSpecialCharacters() {
        #expect(ShellQuote.quote("a b") == "'a b'")
        #expect(ShellQuote.quote("x'y") == "'x'\"'\"'y'")
        #expect(ShellQuote.quote("$(echo secret)") == "'$(echo secret)'")
    }
    @Test func legacyPreferencesKeepChoices() throws {
        let old=#"{"hours":8,"screenOff":false,"cleanup":true,"backgroundHistory":false}"#
        let p=try JSONDecoder().decode(UserPreferences.self,from:Data(old.utf8))
        #expect(p.hours==8);#expect(!p.screenOff);#expect(p.cleanup);#expect(!p.backgroundHistory)
        #expect(p.heat==HeatSettings())
    }
    @Test func heatSettingsAreValidatedWithPreferences() {
        var p=UserPreferences();p.heat.holdAt=60;p.heat.resumeAt=70;p.validate()
        #expect(p.heat.holdAt==35);#expect(p.heat.resumeAt==32)
    }
}
