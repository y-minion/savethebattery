import Foundation
/// One charge request from `vbctl` to the running app, sent as a single JSON line.
public struct ControlRequest: Codable, Equatable, Sendable {
    public var command:String;public var value:Int?
    public init(command:String,value:Int?) { self.command=command;self.value=value }
    public init(_ c:ChargeCommand) {
        switch c {
        case .setLimit(let p):self.init(command:"setLimit",value:p)
        case .clearLimit:self.init(command:"clearLimit",value:nil)
        case .startTopUp:self.init(command:"startTopUp",value:nil)
        case .endTopUp:self.init(command:"endTopUp",value:nil)
        }
    }
    /// Only these four charge commands are accepted; anything else is refused before the app acts.
    public func chargeCommand() -> ChargeCommand? {
        let c:ChargeCommand
        switch command {
        case "setLimit":guard let value else { return nil };c = .setLimit(value)
        case "clearLimit":c = .clearLimit
        case "startTopUp":c = .startTopUp
        case "endTopUp":c = .endTopUp
        default:return nil
        }
        return c.isValid ? c:nil
    }
}
public struct ControlResponse: Codable, Equatable, Sendable {
    public var ok:Bool;public var message:String;public var state:ChargeLimitState?
    public init(ok:Bool,message:String,state:ChargeLimitState?) { self.ok=ok;self.message=message;self.state=state }
}
