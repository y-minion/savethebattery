import Foundation
/// What the root helper (and the control socket) send over the wire: a code, never display text.
/// The reader turns it into text in its own language. Text from an older (v2) helper passes through unchanged.
public enum HelperReply: String, CaseIterable, Sendable {
    case limitOutOfRange="limit.outOfRange"
    case limitSaveFailed="limit.saveFailed"
    case lowPowerReadFailed="lowPower.readFailed"
    case lowPowerMissing="lowPower.missing"
    case lowPowerFailed="lowPower.failed"
    case ledValueRejected="led.valueRejected"
    case ledUnsupported="led.unsupported"
    case ledFailed="led.failed"
    case noReply="xpc.noReply"
    case unsupportedRequest="control.unsupported"
    public var text:String {
        switch self {
        case .limitOutOfRange:tr("That charge limit is out of the allowed range.","허용 범위를 벗어난 상한입니다.")
        case .limitSaveFailed:tr("Could not save the setting.","설정을 저장하지 못했습니다.")
        case .lowPowerReadFailed:tr("Could not read the Low Power Mode setting.","저전력 모드 설정을 읽지 못했습니다.")
        case .lowPowerMissing:tr("Could not find the Low Power Mode setting on this Mac.","이 맥에서 저전력 모드 설정을 찾지 못했습니다.")
        case .lowPowerFailed:tr("Could not change Low Power Mode.","저전력 모드를 바꾸지 못했습니다.")
        case .ledValueRejected:tr("That LED value is not allowed.","허용되지 않은 LED 값입니다.")
        case .ledUnsupported:tr("This Mac's MagSafe LED cannot be changed.","이 맥에서는 MagSafe LED를 바꿀 수 없습니다.")
        case .ledFailed:tr("Could not change the MagSafe LED.","MagSafe LED를 바꾸지 못했습니다.")
        case .noReply:tr("Could not reach the helper, or it did not answer within 3 seconds.","헬퍼에 연결하지 못했거나 3초 안에 응답이 없습니다.")
        case .unsupportedRequest:tr("This request is not supported.","지원하지 않는 요청입니다.")
        }
    }
    /// Text to show for a wire value: a known code gives its text, anything else (a v2 sentence) is kept as is.
    public static func display(_ wire:String?) -> String? {
        guard let wire else { return nil }
        return HelperReply(rawValue:wire)?.text ?? wire
    }
}
