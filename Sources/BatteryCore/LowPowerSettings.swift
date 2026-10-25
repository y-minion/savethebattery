import Foundation
/// The Low Power Mode lines of `pmset -g custom`. Newer macOS names the key
/// `powermode`; older releases use `lowpowermode`.
public struct LowPowerSettings: Equatable, Sendable {
    public var key:String?,battery:Int?,ac:Int?
    public init(key:String?=nil,battery:Int?=nil,ac:Int?=nil) { self.key=key;self.battery=battery;self.ac=ac }
    public static func parse(_ pmsetCustom:String) -> LowPowerSettings {
        var block:String?;var values:[String:[String:Int]]=[:]
        for raw in pmsetCustom.split(whereSeparator:\.isNewline) {
            let line=raw.trimmingCharacters(in:.whitespaces)
            if line.hasSuffix(":") { block=line;continue }
            let parts=line.split(whereSeparator:\.isWhitespace)
            guard let block,parts.count==2,let v=Int(parts[1]) else { continue }
            let name=String(parts[0])
            guard name=="powermode"||name=="lowpowermode" else { continue }
            values[name,default:[:]][block]=v
        }
        guard let key=["powermode","lowpowermode"].first(where:{ values[$0] != nil }) else { return LowPowerSettings() }
        return LowPowerSettings(key:key,battery:values[key]?["Battery Power:"],ac:values[key]?["AC Power:"])
    }
    /// The user picked a per-source setting ("only on battery" and so on); a switch overrides it.
    public var isConditional:Bool { battery != ac }
    /// `pmset` argv (without the program) that turns Low Power Mode on or off for every power source.
    public func arguments(on:Bool) -> [String]? { key.map { ["-a",$0,on ? "1":"0"] } }
}
