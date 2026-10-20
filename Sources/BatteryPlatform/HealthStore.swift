import Foundation
import BatteryCore
/// A private JSON file. A file that cannot be decoded is moved to `<name>.corrupt-<time>-<id>` and treated as empty.
public struct JSONFile<T: Codable> {
    public let url: URL
    public init(url: URL) { self.url = url }
    /// `repair: false` (read-only callers such as the CLI) leaves an unreadable file where it is.
    public func load(repair: Bool = true) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(T.self, from: data) { return value }
        if repair {
            let aside = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).corrupt-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))")
            try? FileManager.default.moveItem(at: url, to: aside)
        }
        return nil
    }
    public func save(_ value: T) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func delete() throws { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
}
public struct HealthFile: Codable, Sendable {
    public var version = 1
    public var last: BatterySnapshot?
    public var days: [DailyUsage] = []
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        last = try c.decodeIfPresent(BatterySnapshot.self, forKey: .last)
        days = try c.decodeIfPresent([DailyUsage].self, forKey: .days) ?? []
    }
}
public struct HealthStore {
    let file: JSONFile<HealthFile>
    public init(url: URL) { file = JSONFile(url: url) }
    public func read(repair: Bool = true) -> HealthFile { file.load(repair: repair) ?? HealthFile() }
    public func save(_ value: HealthFile) throws { try file.save(value) }
    public func delete() throws { try file.delete() }
}
/// Keeps the daily ledger in memory and writes it at most every five minutes, plus on `flush()`.
public final class HealthRecorder {
    public static let saveInterval: TimeInterval = 300
    public private(set) var file: HealthFile
    let store: HealthStore
    var savedAt: Date?
    public init(store: HealthStore) { self.store = store; file = store.read() }
    public func record(_ sample: BatterySnapshot, calendar: Calendar = .current) throws {
        file.days = HealthLedger.record(sample, after: file.last, into: file.days, calendar: calendar)
        file.last = sample
        if let s = savedAt, abs(sample.timestamp.timeIntervalSince(s)) < Self.saveInterval { return }
        try store.save(file); savedAt = sample.timestamp
    }
    public func flush() throws { try store.save(file); savedAt = file.last?.timestamp }
    public func reset() throws { try store.delete(); file = HealthFile(); savedAt = nil }
}
public struct SleepStore {
    public static let limit = 30
    let file: JSONFile<[SleepEvent]>
    public init(url: URL) { file = JSONFile(url: url) }
    public func read(repair: Bool = true) -> [SleepEvent] { file.load(repair: repair) ?? [] }
    public func append(_ event: SleepEvent) throws { try file.save(Array((read() + [event]).suffix(Self.limit))) }
    public func delete() throws { try file.delete() }
}
