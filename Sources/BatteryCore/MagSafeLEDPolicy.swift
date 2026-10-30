import Foundation
public enum LEDColor: String, Codable, CaseIterable, Sendable {
    case green, orange, off
    public var led: MagSafeLED { switch self { case .green: .green; case .orange: .orange; case .off: .off } }
    public var title: String { switch self { case .green: tr("Green","초록"); case .orange: tr("Orange","주황"); case .off: tr("Off","꺼짐") } }
}
public enum LEDMode: String, Codable, CaseIterable, Sendable {
    case system, off, perState
    public var title: String { switch self { case .system: tr("macOS default","macOS 기본"); case .off: tr("Off","끄기"); case .perState: tr("Set per state","상태별로 정하기") } }
}
public struct LEDSettings: Codable, Equatable, Sendable {
    public var mode = LEDMode.system
    public var charging = LEDColor.orange
    public var paused = LEDColor.green
    public var heat = LEDColor.orange
    public init() {}
    // Each field falls back alone, so an unknown value never discards the rest.
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        mode=(try? c.decodeIfPresent(LEDMode.self,forKey:.mode)) ?? .system
        charging=(try? c.decodeIfPresent(LEDColor.self,forKey:.charging)) ?? .orange
        paused=(try? c.decodeIfPresent(LEDColor.self,forKey:.paused)) ?? .green
        heat=(try? c.decodeIfPresent(LEDColor.self,forKey:.heat)) ?? .orange
    }
}
public enum MagSafeLEDPolicy {
    /// nil means "leave the LED to macOS".
    public static func target(_ s: LEDSettings, status: MenuBarStatus) -> MagSafeLED? {
        switch s.mode {
        case .system: return nil
        case .off: return .off
        case .perState:
            switch status { case .charging: return s.charging.led; case .paused: return s.paused.led; case .heatHold: return s.heat.led; case .onBattery: return nil }
        }
    }
    /// The value to write now, or nil when nothing changed. `dirty` means an earlier run may have left a non-system value behind.
    public static func write(target: MagSafeLED?, last: MagSafeLED?, dirty: Bool, unsupported: Bool = false) -> MagSafeLED? {
        if unsupported { return nil }
        if let target { return target == last ? nil : target }
        return dirty && last != .system ? .system : nil
    }
}
public enum MagSafeLEDText {
    /// The sentence a version 2 helper sends for "unsupported". Not UI text (the guard test allows it), kept only so `outcome` still recognises it.
    public static let legacyUnsupportedV2="이 맥에서는 MagSafe LED를 바꿀 수 없습니다."
}
extension MagSafeLEDPolicy {
    /// What a helper reply means for the app. Only the unsupported reply proves nothing was written, so only it clears the dirty flag and stops retries.
    public static func outcome(reply: String?) -> (clearDirty: Bool, unsupported: Bool) {
        let unsupported = reply == HelperReply.ledUnsupported.rawValue || reply == MagSafeLEDText.legacyUnsupportedV2
        return (unsupported, unsupported)
    }
}
