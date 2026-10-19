import Testing
import Foundation
@testable import BatteryPlatform
import BatteryCore
struct PlatformTests {
    @Test func processIdentityGuardsReuseAndOwnership() {
        let p=ProcessIdentity(pid:123,uid:501,started:100)
        let reused = ProcessIdentity(pid:123,uid:501,started:101)
        let permitsReusedPID = p.canTerminate(current:reused,user:501,name:"worker")
        #expect(!permitsReusedPID)
        #expect(!p.canTerminate(current:p,user:502,name:"worker"))
        #expect(!p.canTerminate(current:nil,user:501,name:"worker"))
        #expect(!p.canTerminate(current:p,user:501,name:"zsh"))
        #expect(p.canTerminate(current:p,user:501,name:"temporary-worker"))
    }
    @Test func historyRetainsFreshSamplesAndDeletes() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let store=HistoryStore(url:dir.appendingPathComponent("history.json"))
        var old=BatterySnapshot(); old.timestamp=Date().addingTimeInterval(-8*86400)
        var fresh=BatterySnapshot(); fresh.percent=71
        try store.append(old); try store.append(fresh)
        #expect(store.read().map(\.percent) == [71])
        try store.delete(); #expect(store.read().isEmpty)
    }
    @Test func corruptHistoryDoesNotFabricateValues() throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        try Data("broken".utf8).write(to:file)
        #expect(HistoryStore(url:file).read().isEmpty)
    }
}
