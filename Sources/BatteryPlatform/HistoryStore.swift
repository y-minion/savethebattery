import Foundation
import BatteryCore
public struct HistoryStore {
    public let url: URL
    public init(url: URL) { self.url=url }
    public func append(_ sample: BatterySnapshot) throws {
        var samples=read()
        if let last=samples.last, sample.timestamp.timeIntervalSince(last.timestamp)<60 { return }
        samples.append(sample)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try JSONEncoder().encode(samples).write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
    public func read(now: Date = Date()) -> [BatterySnapshot] {
        guard let data=try? Data(contentsOf:url), let records=try? JSONDecoder().decode([BatterySnapshot].self,from:data) else { return [] }
        return records.filter { now.timeIntervalSince($0.timestamp)>=0 && now.timeIntervalSince($0.timestamp)<=7*86400 }
    }
    public func delete() throws { if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) } }
}
