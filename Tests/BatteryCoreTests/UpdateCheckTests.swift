import Testing
import Foundation
import BatteryCore
struct UpdateCheckTests {
    @Test func semver() {
        #expect(UpdateCheck.newer(latestTag:"v0.10.0",current:"0.9.0") != nil)
        #expect(UpdateCheck.newer(latestTag:"v0.2.0",current:"0.2.0") == nil)
        #expect(UpdateCheck.newer(latestTag:"0.2.0",current:"0.1.0") != nil)
        #expect(UpdateCheck.newer(latestTag:"v0.2.0-beta.1",current:"0.2.0") == nil)
        #expect(UpdateCheck.newer(latestTag:"v0.3.0-beta.1",current:"0.2.0") != nil)
        #expect(UpdateCheck.newer(latestTag:"nightly",current:"0.2.0") == nil)
        #expect(UpdateCheck.newer(latestTag:"v1.0",current:"0.2.0") == nil)
    }
    @Test func prefsDefaultOnAndOldFilesDecode() throws {
        let p = try JSONDecoder().decode(UserPreferences.self, from: Data("{}".utf8)); #expect(p.checkUpdates)
        let off = try JSONDecoder().decode(UserPreferences.self, from: Data(#"{"checkUpdates":false}"#.utf8)); #expect(!off.checkUpdates)
    }
    @Test func preReleaseAndSignedParts() {
        #expect(UpdateCheck.newer(latestTag:"v0.3.0-beta.10",current:"0.3.0-beta.2") != nil)
        #expect(UpdateCheck.newer(latestTag:"v0.3.0-beta.2",current:"0.3.0-beta.10") == nil)
        #expect(SemVer("v+1.0.0") == nil)
        #expect(SemVer("1.-2.0") == nil)
    }
    @Test func dueAfterAFullInterval() {
        let t=Date(timeIntervalSince1970:1_790_000_000)
        #expect(UpdateCheck.isDue(last:nil,now:t))
        #expect(!UpdateCheck.isDue(last:t,now:t.addingTimeInterval(UpdateCheck.interval-1)))
        #expect(UpdateCheck.isDue(last:t,now:t.addingTimeInterval(UpdateCheck.interval)))
    }
    @Test func trustedReleaseURL() {
        let ok={ (s:String) in UpdateCheck.isTrustedReleaseURL(URL(string:s)!) }
        #expect(ok("https://github.com/y-minion/vibebattery/releases/tag/v0.2.0"))
        #expect(ok("https://GitHub.com/y-minion/vibebattery/releases/tag/v0.2.0"))
        #expect(!ok("http://github.com/y-minion/vibebattery/releases/tag/v0.2.0"))
        #expect(!ok("https://evil.com/y-minion/vibebattery/releases/x"))
        #expect(!ok("https://github.com.evil.com/y-minion/vibebattery/releases/x"))
        #expect(!ok("https://github.com/other/repo/releases/x"))
    }
}
