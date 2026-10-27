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
}
