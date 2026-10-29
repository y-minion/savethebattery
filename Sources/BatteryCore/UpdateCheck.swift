import Foundation
/// `MAJOR.MINOR.PATCH` with an optional leading `v` and `-pre` suffix; a pre-release sorts below its core.
public struct SemVer: Comparable, Sendable {
    let core:[Int];let pre:String?
    public var description:String { core.map(String.init).joined(separator:".")+(pre.map{"-"+$0} ?? "") }
    public init?(_ tag:String) {
        var s=Substring(tag);if s.hasPrefix("v") { s=s.dropFirst() }
        let parts=s.split(separator:"-",maxSplits:1,omittingEmptySubsequences:false)
        let nums=parts[0].split(separator:".",omittingEmptySubsequences:false).map { $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) ? Int($0) : nil }
        guard nums.count==3,!nums.contains(nil) else { return nil }
        if parts.count==2 && parts[1].isEmpty { return nil }
        core=nums.compactMap{$0};pre=parts.count==2 ? String(parts[1]) : nil
    }
    public static func < (a:SemVer,b:SemVer) -> Bool {
        if a.core != b.core { return a.core.lexicographicallyPrecedes(b.core) }
        switch (a.pre,b.pre) { case let (x?,y?): return preLess(x,y); case (.some,nil): return true; default: return false }
    }
}
extension SemVer {
    /// SemVer precedence: dot-separated identifiers, numeric ones numerically and below alphanumeric ones.
    static func preLess(_ x:String,_ y:String) -> Bool {
        let a=x.split(separator:".",omittingEmptySubsequences:false),b=y.split(separator:".",omittingEmptySubsequences:false)
        for (p,q) in zip(a,b) where p != q {
            switch (Int(p),Int(q)) { case let (m?,n?): return m<n; case (.some,nil): return true; case (nil,.some): return false; default: return p<q }
        }
        return a.count<b.count
    }
}
public enum UpdateCheck {
    public static let interval:TimeInterval=86_400
    /// A timer does not fire during sleep, so a wake checks again once a full interval has passed since the last attempt.
    public static func isDue(last:Date?,now:Date) -> Bool { last.map { now.timeIntervalSince($0) >= interval } ?? true }
    public static let installCommand="curl -fsSL https://github.com/y-minion/savethebattery/releases/latest/download/install.sh | sh"
    /// Only releases of this repository on github.com may be opened from the update notice.
    public static func isTrustedReleaseURL(_ url:URL) -> Bool {
        url.scheme=="https" && url.host?.lowercased()=="github.com" && url.path.hasPrefix("/y-minion/savethebattery/releases/")
    }
    /// The latest version when it is newer than `current`; nil for unparsable tags or no upgrade.
    public static func newer(latestTag:String,current:String) -> SemVer? {
        guard let l=SemVer(latestTag),let c=SemVer(current),l>c else { return nil }
        return l
    }
}
