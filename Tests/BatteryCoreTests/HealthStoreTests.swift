import Testing
import Foundation
@testable import BatteryCore
@testable import BatteryPlatform
struct HealthStoreTests {
    func dir() -> URL { let u=FileManager.default.temporaryDirectory.appendingPathComponent("vb-health-\(UUID().uuidString)");return u }
    func snap(_ t:Double,_ p:Int=50) -> BatterySnapshot { var s=BatterySnapshot();s.timestamp=Date(timeIntervalSince1970:1_790_000_000+t);s.percent=p;s.healthPrecise=90;return s }
    @Test func corruptFileIsMovedAside() throws {
        let d=dir();try FileManager.default.createDirectory(at:d,withIntermediateDirectories:true)
        let url=d.appendingPathComponent("health.json");try Data("{oops".utf8).write(to:url)
        #expect(HealthStore(url:url).read().days.isEmpty)
        #expect(FileManager.default.fileExists(atPath:url.appendingPathExtension("corrupt").path))
        #expect(!FileManager.default.fileExists(atPath:url.path))
    }
    @Test func savedFilesArePrivate() throws {
        let url=dir().appendingPathComponent("health.json");let r=HealthRecorder(store:HealthStore(url:url))
        try r.record(snap(0),calendar:.current)
        let mode=try FileManager.default.attributesOfItem(atPath:url.path)[.posixPermissions] as? Int
        #expect(mode==0o600)
    }
    @Test func recorderSavesAtMostEveryFiveMinutes() throws {
        let url=dir().appendingPathComponent("health.json");let store=HealthStore(url:url);let r=HealthRecorder(store:store)
        try r.record(snap(0),calendar:.current);try r.record(snap(30),calendar:.current)
        #expect(store.read().days.reduce(0) { $0+$1.observed }==0);#expect(r.file.days.reduce(0) { $0+$1.observed }==30)
        try r.flush();#expect(store.read().days.reduce(0) { $0+$1.observed }==30)
        try r.record(snap(330),calendar:.current);#expect(store.read().last?.timestamp==snap(330).timestamp)
    }
    @Test func recorderResumesFromSavedFile() throws {
        let url=dir().appendingPathComponent("health.json")
        let a=HealthRecorder(store:HealthStore(url:url));try a.record(snap(0),calendar:.current)
        let b=HealthRecorder(store:HealthStore(url:url));try b.record(snap(30),calendar:.current)
        #expect(b.file.days.reduce(0) { $0+$1.observed }==30)
    }
    @Test func recorderKeepsRecordingAfterClockChange() throws {
        let r=HealthRecorder(store:HealthStore(url:dir().appendingPathComponent("health.json")))
        try r.record(snap(1000),calendar:.current);try r.record(snap(0),calendar:.current);try r.record(snap(30),calendar:.current)
        #expect(r.file.days.reduce(0) { $0+$1.observed }==30)
    }
    @Test func resetDeletesFileAndMemory() throws {
        let url=dir().appendingPathComponent("health.json");let r=HealthRecorder(store:HealthStore(url:url))
        try r.record(snap(0),calendar:.current);try r.reset()
        #expect(r.file.days.isEmpty);#expect(r.file.last==nil);#expect(!FileManager.default.fileExists(atPath:url.path))
    }
    @Test func sleepStoreKeepsThirty() throws {
        let s=SleepStore(url:dir().appendingPathComponent("sleep.json"))
        for i in 0..<35 { try s.append(SleepEvent(before:snap(Double(i)*10000,80),after:snap(Double(i)*10000+7200,79))) }
        let all=s.read();#expect(all.count==30);#expect(all.first?.start==snap(50000).timestamp)
        try s.delete();#expect(s.read().isEmpty)
    }
}
