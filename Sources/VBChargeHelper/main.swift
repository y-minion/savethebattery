import Foundation
import SystemConfiguration
import BatteryCore
import BatteryPlatform
import MacBridge
// Root daemon. Accepts only a bounded limit write and a state read from the
// console user's /Applications/VibeBattery.app; no generic defaults or commands.
final class Service:NSObject,ChargeHelperProtocol {
    let domain=TopoffDomain.name as CFString
    func value(_ key:String) -> CFPropertyList? { CFPreferencesCopyValue(key as CFString,domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost) }
    func setLimit(_ percent:Int,reply:@escaping (String?)->Void) {
        guard let writes=TopoffDomain.writes(limit:percent,existingFeature:value(TopoffDomain.featureKey)) else { return reply("허용 범위를 벗어난 상한입니다.") }
        for (key,v) in writes { CFPreferencesSetValue(key as CFString,v as CFPropertyList,domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost) }
        guard CFPreferencesSynchronize(domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost) else { return reply("설정을 저장하지 못했습니다.") }
        _=vb_notify(TopoffDomain.notification)
        reply(nil)
    }
    func readState(reply:@escaping ([String:String])->Void) {
        var r:[String:String]=[:]
        for key in [TopoffDomain.limitKey,TopoffDomain.featureKey] { r[key]=value(key).map { "\($0)" } ?? "없음" }
        reply(r)
    }
}
final class Gate:NSObject,NSXPCListenerDelegate {
    func listener(_ listener:NSXPCListener,shouldAcceptNewConnection c:NSXPCConnection) -> Bool {
        var console:uid_t=0
        let user=SCDynamicStoreCopyConsoleUser(nil,&console,nil)
        var buffer=[CChar](repeating:0,count:4096)
        let path=vb_pid_path(c.processIdentifier,&buffer,Int32(buffer.count))==0 ? String(cString:buffer):nil
        guard HelperPolicy.allows(clientUID:c.effectiveUserIdentifier,consoleUID:user==nil ? nil:console,clientPath:path) else { return false }
        // The signature check is enforced by XPC on every message, so a PID swap after the path check fails.
        c.setCodeSigningRequirement(HelperPolicy.clientRequirement)
        c.exportedInterface=NSXPCInterface(with:ChargeHelperProtocol.self)
        c.exportedObject=Service()
        c.resume();return true
    }
}
let gate=Gate()
let listener=NSXPCListener(machServiceName:HelperPolicy.label)
listener.delegate=gate;listener.resume()
RunLoop.main.run()
