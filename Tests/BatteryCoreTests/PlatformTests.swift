import Testing
import Foundation
@testable import BatteryPlatform
import BatteryCore
import MacBridge
struct PlatformTests {
    @Test func rawSignalingRejectsUnownedGrandchildren() throws {
        let parent=Process();parent.executableURL=URL(fileURLWithPath:"/bin/sh")
        parent.arguments=["-c", "sleep 15 & kid=$!; trap 'kill \"$kid\" 2>/dev/null; wait; exit' TERM; echo $kid; wait"]
        let output=Pipe();parent.standardOutput=output
        try parent.run()
        defer { parent.terminate();parent.waitUntilExit() }
        let text=String(data:output.fileHandleForReading.availableData,encoding:.utf8) ?? ""
        let pid=try #require(Int32(text.trimmingCharacters(in:.whitespacesAndNewlines)))
        let identity=try #require(ProcessReader.one(pid)?.identity)
        #expect(vb_signal(pid,identity.started,0)==EPERM)
    }
    @Test func processIdentityGuardsReuseAndOwnership() {
        let p=ProcessIdentity(pid:123,uid:501,started:100)
        let reused = ProcessIdentity(pid:123,uid:501,started:101)
        let permitsReusedPID = p.canTerminate(current:reused,user:501,name:"worker")
        #expect(!permitsReusedPID)
        #expect(!p.canTerminate(current:p,user:502,name:"worker"))
        #expect(!p.canTerminate(current:nil,user:501,name:"worker"))
        #expect(!p.canTerminate(current:p,user:501,name:"zsh"))
        #expect(!p.canTerminate(current:p,user:501,name:"Finder"))
        #expect(!p.canTerminate(current:p,user:501,name:"vbctl"))
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
