import Foundation
import BatteryCore
@objc public protocol ChargeHelperProtocol {
    func setLimit(_ percent:Int,reply:@escaping (String?)->Void)
    func readState(reply:@escaping ([String:String])->Void)
}
public final class XPCChargeHelper: ChargeHelperClient {
    public init() {}
    public var isInstalled:Bool { FileManager.default.fileExists(atPath:HelperPolicy.daemonPlist) }
    private func connect() -> NSXPCConnection {
        let c=NSXPCConnection(machServiceName:HelperPolicy.label,options:.privileged)
        c.remoteObjectInterface=NSXPCInterface(with:ChargeHelperProtocol.self)
        c.setCodeSigningRequirement(HelperPolicy.helperRequirement)
        c.resume();return c
    }
    public func setLimit(_ percent:Int) -> String? {
        let c=connect();defer { c.invalidate() }
        var message:String?="헬퍼가 응답하지 않습니다."
        let proxy=c.synchronousRemoteObjectProxyWithErrorHandler { message="헬퍼 연결 실패: \($0.localizedDescription)" } as? ChargeHelperProtocol
        proxy?.setLimit(percent) { message=$0 }
        return message
    }
    public func readState() -> [String:String]? {
        let c=connect();defer { c.invalidate() }
        var state:[String:String]?
        let proxy=c.synchronousRemoteObjectProxyWithErrorHandler { _ in state=nil } as? ChargeHelperProtocol
        proxy?.readState { state=$0 }
        return state
    }
}
