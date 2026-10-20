import Foundation
import BatteryCore
@objc public protocol ChargeHelperProtocol {
    func setLimit(_ percent:Int,reply:@escaping (String?)->Void)
    func readState(reply:@escaping ([String:String])->Void)
}
public final class XPCChargeHelper: ChargeHelperClient {
    public init() {}
    public var plistInstalled:Bool { FileManager.default.fileExists(atPath:HelperPolicy.daemonPlist) }
    /// Usable for routing only when installed and this app runs where the helper accepts it.
    public var isInstalled:Bool { status(probe:false) == .ready }
    public func status(probe:Bool=true) -> HelperStatus {
        HelperStatus.evaluate(installed:plistInstalled,appPath:Bundle.main.bundlePath,probe:{ !probe || readState() != nil })
    }
    private func connect() -> NSXPCConnection {
        let c=NSXPCConnection(machServiceName:HelperPolicy.label,options:.privileged)
        c.remoteObjectInterface=NSXPCInterface(with:ChargeHelperProtocol.self)
        c.setCodeSigningRequirement(HelperPolicy.helperRequirement)
        c.resume();return c
    }
    // Bounded wait: a stalled helper must not freeze the app's main thread.
    private func call<T>(_ fallback:T,_ body:(ChargeHelperProtocol,@escaping (T)->Void)->Void) -> T {
        let c=connect();defer { c.invalidate() }
        let done=DispatchSemaphore(value:0);let lock=NSLock();var result=fallback
        let finish:(T)->Void={ v in lock.lock();result=v;lock.unlock();done.signal() }
        guard let proxy=c.remoteObjectProxyWithErrorHandler({ _ in finish(fallback) }) as? ChargeHelperProtocol else { return fallback }
        body(proxy,finish)
        guard done.wait(timeout:.now()+3) == .success else { return fallback }
        lock.lock();defer { lock.unlock() };return result
    }
    public func setLimit(_ percent:Int) -> String? {
        call("헬퍼에 연결하지 못했거나 3초 안에 응답이 없습니다." as String?) { proxy,finish in proxy.setLimit(percent) { finish($0) } }
    }
    public func readState() -> [String:String]? {
        call(nil as [String:String]?) { proxy,finish in proxy.readState { finish($0) } }
    }
}
