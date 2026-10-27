import Foundation
/// `MAJOR.MINOR.PATCH` with an optional leading `v` and `-pre` suffix; a pre-release sorts below its core.
public struct SemVer: Comparable, Sendable {
    let core:[Int];let pre:String?
    public var description:String { core.map(String.init).joined(separator:".")+(pre.map{"-"+$0} ?? "") }
    public init?(_ tag:String) {
        var s=Substring(tag);if s.hasPrefix("v") { s=s.dropFirst() }
        let parts=s.split(separator:"-",maxSplits:1,omittingEmptySubsequences:false)
        let nums=parts[0].split(separator:".",omittingEmptySubsequences:false).map { Int($0) }
        guard nums.count==3,!nums.contains(nil) else { return nil }
        if parts.count==2 && parts[1].isEmpty { return nil }
        core=nums.compactMap{$0};pre=parts.count==2 ? String(parts[1]) : nil
    }
    public static func < (a:SemVer,b:SemVer) -> Bool {
        if a.core != b.core { return a.core.lexicographicallyPrecedes(b.core) }
        switch (a.pre,b.pre) { case let (x?,y?): return x<y; case (.some,nil): return true; default: return false }
    }
}
public enum UpdateCheck {
    public static let interval:TimeInterval=86_400
    public static let installCommand="curl -fsSL https://github.com/y-minion/vibebattery/releases/latest/download/install.sh | sh"
    /// The latest version when it is newer than `current`; nil for unparsable tags or no upgrade.
    public static func newer(latestTag:String,current:String) -> SemVer? {
        guard let l=SemVer(latestTag),let c=SemVer(current),l>c else { return nil }
        return l
    }
}
