import Foundation
import BatteryCore
public struct SessionRecord: Codable, Identifiable {
    public var id=UUID(); public var command=""; public var owner:ProcessIdentity?
    public var started=Date(); public var deadline=Date().addingTimeInterval(14400)
    public var outcome=SessionOutcome.running; public var cleanup=CleanupPolicy.observe
    public var protected=false; public var exitCode:Int32?; public var ended:Date?
    public init() {}
}
public enum AppPaths {
    public static var directory:URL {
        if let custom=ProcessInfo.processInfo.environment["VIBEBATTERY_DATA_DIR"] { return URL(fileURLWithPath:custom) }
        return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("VibeBattery")
    }
    public static var sessions:SessionStore { SessionStore(directory:directory.appendingPathComponent("sessions")) }
    public static var health:URL { directory.appendingPathComponent("health.json") }
    public static var sleep:URL { directory.appendingPathComponent("sleep.json") }
    public static var notify:URL { directory.appendingPathComponent("notify.json") }
    public static var schedule:URL { directory.appendingPathComponent("schedule.json") }
    public static var controlSocket:URL { directory.appendingPathComponent("control.sock") }
}
public struct SessionStore {
    public let directory: URL
    public init(directory:URL) { self.directory=directory }
    private func prepare() throws {
        let fm=FileManager.default
        if fm.fileExists(atPath:directory.path) {
            let a=try fm.attributesOfItem(atPath:directory.path)
            guard a[.type] as? FileAttributeType == .typeDirectory,(a[.ownerAccountID] as? NSNumber)?.uint32Value==geteuid() else { throw PlatformError.message(tr("The session folder is not safe.","안전하지 않은 세션 폴더입니다.")) }
        }
        try fm.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)
    }
    private func file(_ id:UUID) -> URL { directory.appendingPathComponent(id.uuidString+".json") }
    public func save(_ record:SessionRecord) throws {
        try prepare();try JSONEncoder().encode(record).write(to:file(record.id),options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file(record.id).path)
    }
    public func load(_ id:UUID) -> SessionRecord? {
        let f=file(id)
        guard let a=try? FileManager.default.attributesOfItem(atPath:f.path),a[.type] as? FileAttributeType == .typeRegular,
              (a[.ownerAccountID] as? NSNumber)?.uint32Value==geteuid(),(a[.size] as? NSNumber)?.intValue ?? Int.max < 100000,
              let data=try? Data(contentsOf:f),let r=try? JSONDecoder().decode(SessionRecord.self,from:data),r.id==id else { return nil }
        return r
    }
    public func all() -> [SessionRecord] {
        let files=(try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)) ?? []
        return files.filter { $0.pathExtension=="json" }.compactMap { UUID(uuidString:$0.deletingPathExtension().lastPathComponent) }.compactMap(load).sorted { $0.started>$1.started }
    }
    public func removeInactive(before cutoff:Date) throws {
        for record in all() where (record.ended ?? record.started)<cutoff {
            if let owner=record.owner,ProcessReader.one(owner.pid)?.identity==owner { continue }
            try FileManager.default.removeItem(at:file(record.id))
            let marker=directory.appendingPathComponent(record.id.uuidString+".release")
            if FileManager.default.fileExists(atPath:marker.path) { try FileManager.default.removeItem(at:marker) }
        }
    }
    public func release(_ id:UUID) throws {
        guard load(id) != nil else { throw PlatformError.message(tr("Session not found.","세션을 찾을 수 없습니다.")) }
        try prepare();let f=directory.appendingPathComponent(id.uuidString+".release")
        try Data().write(to:f,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:f.path)
    }
    public func isReleased(_ id:UUID) -> Bool { FileManager.default.fileExists(atPath:directory.appendingPathComponent(id.uuidString+".release").path) }
}
