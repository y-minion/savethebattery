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
    /// A source is set to High Power (`powermode` 2); turning the switch off writes automatic (0) there.
    public var isHighPower:Bool { key == "powermode" && (battery == 2 || ac == 2) }
    /// `pmset` argv (without the program) that turns Low Power Mode on or off for every power source.
    public func arguments(on:Bool) -> [String]? { key.map { ["-a",$0,on ? "1":"0"] } }
}
/// Screen text for the Low Power Mode switch.
public enum LowPowerText {
    public static var needsUpdate:String { tr("Reinstall the helper: this version only accepts the official VibeBattery app.","헬퍼를 다시 설치해 주세요. 이 버전은 공식 VibeBattery 앱만 받아들입니다.") }
    public static var failed:String { tr("Could not change Low Power Mode.","저전력 모드를 바꾸지 못했습니다.") }
    public static var conditional:String { tr("It is currently set differently for battery and power adapter. Changing it here makes it always on or always off.","지금은 배터리/전원 어댑터에 따라 다르게 설정되어 있습니다. 여기서 바꾸면 항상 켜짐 또는 항상 꺼짐이 됩니다.") }
    /// Why the switch is unavailable; nil when the helper is ready.
    public static func caption(_ s:HelperStatus) -> String? {
        switch s { case .ready:nil; case .outdated:tr("Helper update needed","헬퍼 업데이트가 필요합니다"); default:tr("Install the helper to change this here.","헬퍼를 설치하면 여기서 바로 바꿀 수 있습니다") }
    }
    public static var highPower:String { tr("Turning it off here switches to Automatic instead of High Power.","여기서 끄면 고성능 대신 자동으로 바뀝니다.") }
    /// Captions to show under the switch.
    public static func notes(_ s:LowPowerSettings) -> [String] { (s.isConditional ? [conditional]:[])+(s.isHighPower ? [highPower]:[]) }
    /// Text for a switch request that cannot go to the helper; never the "update" text for a missing or unreachable helper.
    public static func unavailable(_ s:HelperStatus) -> String {
        switch s {
        case .ready:failed
        case .outdated:needsUpdate
        case .unreachable:tr("Could not reach the helper. Check again in Settings › Charge.","헬퍼에 연결하지 못했습니다. 설정 › 충전에서 다시 확인해 주세요.")
        case .wrongLocation:tr("Move the app to /Applications to use the helper.","앱을 /Applications에 옮겨야 헬퍼를 쓸 수 있습니다.")
        case .notInstalled:caption(s) ?? failed
        }
    }
    public static func done(_ on:Bool) -> String { on ? tr("Low Power Mode turned on.","저전력 모드를 켰습니다."):tr("Low Power Mode turned off.","저전력 모드를 껐습니다.") }
}
