import Foundation
public struct UserPreferences: Codable {
    public var hours=4.0;public var screenOff=true;public var cleanup=false;public var backgroundHistory=true
    public var heat=HeatSettings()
    public init() {}
    // Files written before a field existed must keep the user's other choices.
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        hours=try c.decodeIfPresent(Double.self,forKey:.hours) ?? 4
        screenOff=try c.decodeIfPresent(Bool.self,forKey:.screenOff) ?? true
        cleanup=try c.decodeIfPresent(Bool.self,forKey:.cleanup) ?? false
        backgroundHistory=try c.decodeIfPresent(Bool.self,forKey:.backgroundHistory) ?? true
        heat=try c.decodeIfPresent(HeatSettings.self,forKey:.heat) ?? HeatSettings()
    }
    public mutating func validate() { if !hours.isFinite || hours<=0 || hours>168 { hours=4 };heat.validate() }
}
public enum ShellQuote {
    public static func quote(_ s:String) -> String { "'"+s.replacingOccurrences(of:"'",with:"'\"'\"'")+"'" }
}
