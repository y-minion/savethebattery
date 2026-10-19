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
}
