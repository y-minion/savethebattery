import Foundation
public struct UserPreferences: Codable {
    public var hours=4.0;public var screenOff=true;public var cleanup=false;public var backgroundHistory=true
    public init() {}
    public mutating func validate() { if !hours.isFinite || hours<=0 || hours>168 { hours=4 } }
}
public enum ShellQuote {
    public static func quote(_ s:String) -> String { "'"+s.replacingOccurrences(of:"'",with:"'\"'\"'")+"'" }
}
