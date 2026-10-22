import Foundation
/// `vbctl charge …` arguments. Writes go to the running app; `status` reads directly.
public enum ChargeCLI {
    public enum Action: Equatable { case status(json:Bool), request(ControlRequest) }
    public struct UsageError: Error, Equatable { public let text:String }
    public static let usage="""
    사용법:
      vbctl charge status [--json]
      vbctl charge set <50-100>   (5 단위)
      vbctl charge off
      vbctl charge topup
      vbctl charge end
    """
    /// `args` are the words after `charge`; the failure is the usage text.
    public static func parse(_ args:[String]) -> Result<Action,UsageError> {
        switch args {
        case ["status"]:return .success(.status(json:false))
        case ["status","--json"]:return .success(.status(json:true))
        case ["off"]:return .success(.request(ControlRequest(.clearLimit)))
        case ["topup"]:return .success(.request(ControlRequest(.startTopUp)))
        case ["end"]:return .success(.request(ControlRequest(.endTopUp)))
        default:
            if args.count==2,args[0]=="set",let p=Int(args[1]),ChargeCommand.setLimit(p).isValid { return .success(.request(ControlRequest(.setLimit(p)))) }
            return .failure(UsageError(text:usage))
        }
    }
}
