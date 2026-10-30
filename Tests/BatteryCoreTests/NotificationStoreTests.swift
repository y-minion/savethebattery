import Testing
import Foundation
@testable import BatteryCore
@testable import BatteryPlatform
struct NotificationStoreTests {
    func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("stb-notify-\(UUID().uuidString)/notify.json") }
    @Test func savesPrivatelyAndOnlyWhenChanged() throws {
        let u=url();let store=NotificationStore(url:u)
        var m=store.read();#expect(m==NotificationMemory())
        m.hotArmed=false;#expect(try store.save(m))
        #expect(try FileManager.default.attributesOfItem(atPath:u.path)[.posixPermissions] as? Int==0o600)
        m.evaluated=Date();m.wasCharging=true
        #expect(try store.save(m)==false)
        #expect(NotificationStore(url:u).read().hotArmed==false)
    }
    @Test func corruptMemoryIsMovedAside() throws {
        let u=url();try FileManager.default.createDirectory(at:u.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("{oops".utf8).write(to:u)
        #expect(NotificationStore(url:u).read()==NotificationMemory())
        #expect(try FileManager.default.contentsOfDirectory(atPath:u.deletingLastPathComponent().path).contains { $0.hasPrefix("notify.json.corrupt-") })
    }
    @Test func pathLivesInDataDirectory() { #expect(AppPaths.notify.lastPathComponent=="notify.json") }
}
