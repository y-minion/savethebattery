import Testing
import Foundation
import BatteryPlatform
struct AppInstallTests {
    func dir() throws -> URL {
        let u=FileManager.default.temporaryDirectory.appendingPathComponent("stb-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:u,withIntermediateDirectories:true);return u
    }
    func bundle(_ u:URL,_ text:String) throws {
        try FileManager.default.createDirectory(at:u.appendingPathComponent("Contents"),withIntermediateDirectories:true)
        try Data(text.utf8).write(to:u.appendingPathComponent("Contents/marker"))
    }
    func marker(_ u:URL) -> String? { (try? String(contentsOf:u.appendingPathComponent("Contents/marker"),encoding:.utf8)) }
    @Test func swapReplacesAndKeepsTheOldCopyAside() throws {
        let d=try dir();defer { try? FileManager.default.removeItem(at:d) }
        let src=d.appendingPathComponent("src/App.app"),dest=d.appendingPathComponent("apps/App.app")
        try bundle(src,"new");try bundle(dest,"old")
        let q=src.appendingPathComponent("Contents/marker").path
        #expect(setxattr(q,"com.apple.quarantine","0083;0;test;",12,0,0)==0)
        let old=try BundleSwap.install(src,at:dest)
        #expect(marker(dest)=="new")
        #expect(old.map(marker)=="old")
        #expect(old?.lastPathComponent==".App.app.old")
        #expect(getxattr(dest.appendingPathComponent("Contents/marker").path,"com.apple.quarantine",nil,0,0,0) == -1)
        #expect(!FileManager.default.fileExists(atPath:d.appendingPathComponent("apps/.App.app.new").path))
        #expect(marker(src)=="new")
    }
    @Test func swapIntoAnEmptyPlaceHasNoOldCopy() throws {
        let d=try dir();defer { try? FileManager.default.removeItem(at:d) }
        let src=d.appendingPathComponent("App.app"),dest=d.appendingPathComponent("apps/App.app")
        try FileManager.default.createDirectory(at:dest.deletingLastPathComponent(),withIntermediateDirectories:true)
        try bundle(src,"new")
        #expect(try BundleSwap.install(src,at:dest)==nil)
        #expect(marker(dest)=="new")
    }
    @Test func swapMarksTheCopyAsNew() throws {
        let d=try dir();defer { try? FileManager.default.removeItem(at:d) }
        let src=d.appendingPathComponent("App.app"),dest=d.appendingPathComponent("apps/App.app")
        try FileManager.default.createDirectory(at:dest.deletingLastPathComponent(),withIntermediateDirectories:true)
        try bundle(src,"new")
        try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSinceNow:-86_400*30)],ofItemAtPath:src.path)
        _=try BundleSwap.install(src,at:dest)
        let date=try FileManager.default.attributesOfItem(atPath:dest.path)[.modificationDate] as? Date
        #expect(date.map { $0.timeIntervalSinceNow > -60 }==true)
    }
    @Test func failedCopyLeavesTheInstalledAppAlone() throws {
        let d=try dir();defer { try? FileManager.default.removeItem(at:d) }
        let dest=d.appendingPathComponent("apps/App.app");try bundle(dest,"old")
        #expect(throws:BundleSwap.Failure.self) { try BundleSwap.install(d.appendingPathComponent("missing.app"),at:dest) }
        #expect(marker(dest)=="old")
        #expect(!FileManager.default.fileExists(atPath:d.appendingPathComponent("apps/.App.app.new").path))
        #expect(!FileManager.default.fileExists(atPath:d.appendingPathComponent("apps/.App.app.old").path))
    }
    @Test func relaunchDropsTestSettings() async throws {
        let d=try dir();defer { try? FileManager.default.removeItem(at:d) }
        let dump=d.appendingPathComponent("dump.sh"),out=d.appendingPathComponent("env.txt")
        try Data("#!/bin/sh\nenv > \"$1\"\n".utf8).write(to:dump)
        try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:dump.path)
        setenv("STB_TEST_LEAK","1",1);defer { unsetenv("STB_TEST_LEAK") }
        try Relauncher.openAfterExit(out,removing:[],pid:99_999_999,opener:dump.path)
        for _ in 0..<40 where !FileManager.default.fileExists(atPath:out.path) { try await Task.sleep(for:.milliseconds(100)) }
        let env=try String(contentsOf:out,encoding:.utf8)
        #expect(!env.contains("STB_TEST_LEAK"))
        #expect(env.contains("PATH="))
    }
    @Test func relaunchWaitsForTheProcessThenCleansUp() async throws {
        let d=try dir();defer { try? FileManager.default.removeItem(at:d) }
        let waiter=Process();waiter.executableURL=URL(fileURLWithPath:"/bin/sleep");waiter.arguments=["0.6"];try waiter.run()
        let opened=d.appendingPathComponent("opened"),junk=d.appendingPathComponent("junk dir")
        try FileManager.default.createDirectory(at:junk,withIntermediateDirectories:true)
        try Relauncher.openAfterExit(opened,removing:[junk],pid:waiter.processIdentifier,opener:"/usr/bin/touch")
        try await Task.sleep(for:.milliseconds(250))
        #expect(!FileManager.default.fileExists(atPath:opened.path))
        for _ in 0..<40 where !FileManager.default.fileExists(atPath:opened.path) || FileManager.default.fileExists(atPath:junk.path) { try await Task.sleep(for:.milliseconds(100)) }
        #expect(FileManager.default.fileExists(atPath:opened.path))
        #expect(!FileManager.default.fileExists(atPath:junk.path))
    }
}
