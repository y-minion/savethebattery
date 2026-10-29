import Foundation
/// `stb charge …` arguments. Writes go to the running app; `status` reads directly.
public enum ChargeCLI {
    public enum Action: Equatable { case status(json:Bool), request(ControlRequest) }
    public struct UsageError: Error, Equatable { public let text:String }
    public static var usage:String { tr("""
    Usage:
      stb charge status [--json]
      stb charge set <50-100>   (steps of 5)
      stb charge off
      stb charge topup
      stb charge end
    ""","""
    사용법:
      stb charge status [--json]
      stb charge set <50-100>   (5 단위)
      stb charge off
      stb charge topup
      stb charge end
    """) }
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
