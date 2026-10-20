import Foundation
import BatteryCore
/// `notify.json`: written only when the saved fields change, not on every refresh.
public final class NotificationStore {
    let file:JSONFile<NotificationMemory>
    private var saved:Data?
    public init(url:URL) { file=JSONFile(url:url) }
    public func read() -> NotificationMemory { let m=file.load() ?? NotificationMemory();saved=Self.key(m);return m }
    @discardableResult public func save(_ m:NotificationMemory) throws -> Bool {
        let k=Self.key(m);guard k != saved else { return false }
        try file.save(m);saved=k;return true
    }
    /// Sorted keys so dictionary order cannot cause a rewrite.
    static func key(_ m:NotificationMemory) -> Data? { let e=JSONEncoder();e.outputFormatting = .sortedKeys;return try? e.encode(m) }
}
