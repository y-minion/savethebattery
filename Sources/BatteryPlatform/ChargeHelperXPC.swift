import Foundation
import BatteryCore
@objc public protocol ChargeHelperProtocol {
    func setLimit(_ percent:Int,reply:@escaping (String?)->Void)
    func readState(reply:@escaping ([String:String])->Void)
    // Protocol version 2. A version 1 helper does not answer these.
    func version(reply:@escaping (Int)->Void)
    func setLowPowerMode(_ on:Bool,reply:@escaping (String?)->Void)
    func setMagSafeLED(_ raw:Int,reply:@escaping (String?)->Void)
}
public final class XPCChargeHelper: ChargeHelperClient {
    public init() {}
    public var plistInstalled:Bool { FileManager.default.fileExists(atPath:HelperPolicy.daemonPlist) }
    /// Usable for routing only when installed and this app runs where the helper accepts it.
    public var isInstalled:Bool { status(probe:false).canSetLimit }
    /// Without a probe nothing is sent, so the version is assumed current.
    public func status(probe:Bool=true) -> HelperStatus {
        HelperStatus.evaluate(installed:plistInstalled,appPath:Bundle.main.bundlePath,probe:{ !probe || readState() != nil },
                              version:{ probe ? helperVersion():HelperPolicy.protocolVersion })
    }
    private func connect() -> NSXPCConnection {
        let c=NSXPCConnection(machServiceName:HelperPolicy.label,options:.privileged)
        c.remoteObjectInterface=NSXPCInterface(with:ChargeHelperProtocol.self)
        c.setCodeSigningRequirement(HelperPolicy.helperRequirement(team:CodeSigningIdentity.ownTeamID()))
        c.resume();return c
    }
    // Bounded wait: a stalled helper must not freeze the app's main thread.
    private func call<T>(_ fallback:T,timeout:TimeInterval=3,_ body:(ChargeHelperProtocol,@escaping (T)->Void)->Void) -> T {
        let c=connect();defer { c.invalidate() }
        let done=DispatchSemaphore(value:0);let lock=NSLock();var result=fallback
        let finish:(T)->Void={ v in lock.lock();result=v;lock.unlock();done.signal() }
        guard let proxy=c.remoteObjectProxyWithErrorHandler({ _ in finish(fallback) }) as? ChargeHelperProtocol else { return fallback }
        body(proxy,finish)
        guard done.wait(timeout:.now()+timeout) == .success else { return fallback }
        lock.lock();defer { lock.unlock() };return result
    }
    private static let noReply=HelperReply.noReply.rawValue
    public func setLimit(_ percent:Int) -> String? {
        call(Self.noReply as String?) { proxy,finish in proxy.setLimit(percent) { finish($0) } }
    }
    /// nil from a version 1 helper, which does not know the request, or on no reply.
    public func helperVersion() -> Int? {
        call(nil as Int?) { proxy,finish in proxy.version { finish($0) } }
    }
    public func setLowPowerMode(_ on:Bool) -> String? {
        call(Self.noReply as String?) { proxy,finish in proxy.setLowPowerMode(on) { finish($0) } }
    }
    /// `timeout` bounds the wait; the quit path uses a short one so the app still exits promptly.
    public func setMagSafeLED(_ v:MagSafeLED,timeout:TimeInterval=3) -> String? {
        call(Self.noReply as String?,timeout:timeout) { proxy,finish in proxy.setMagSafeLED(v.rawValue) { finish($0) } }
    }
    public func readState() -> [String:String]? {
        call(nil as [String:String]?) { proxy,finish in proxy.readState { finish($0) } }
    }
}
