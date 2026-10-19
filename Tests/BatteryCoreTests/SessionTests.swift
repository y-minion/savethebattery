import Testing
import Foundation
import BatteryCore
import BatteryPlatform
struct SessionTests {
    @Test func commandArgumentsAreNeverShellReparsed() throws {
        let o=try RunOptions.parse(["--hours","2","--cleanup","--","/bin/echo","hello world","$(touch bad)"])
        #expect(o.hours==2); #expect(o.cleanup)
        #expect(o.command == ["/bin/echo","hello world","$(touch bad)"])
    }
    @Test func invalidHoursAndEmptyCommandAreRejected() {
        for args in [["--hours","nan","--","echo"],["--hours","0","--","echo"],["--"],["--bogus","--","echo"]] {
            var rejected=false
            do { _=try RunOptions.parse(args) } catch { rejected=true }
            #expect(rejected)
        }
    }
    @Test func releaseOnlyMarksProtectionNotCompletion() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let store=SessionStore(directory:dir)
        var a=SessionRecord(); a.command="test"; a.protected=true
        let b=SessionRecord();try store.save(a);try store.save(b);try store.release(a.id)
        #expect(store.isReleased(a.id));#expect(!store.isReleased(b.id))
        #expect(store.load(a.id)?.outcome == .running);#expect(store.all().count==2)
    }
}
