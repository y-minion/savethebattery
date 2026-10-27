import Foundation
import SystemConfiguration
import BatteryCore
import BatteryPlatform
import MacBridge
// Root daemon. Accepts only fixed requests (a bounded limit write, a state read, the
// protocol version, Low Power Mode on/off and an allow-listed MagSafe LED value) from the
// console user's /Applications/VibeBattery.app; no generic defaults, keys or commands.
/// The only SMC key the CLI reads; the write path has the key fixed inside MacBridge.
let ledKey="ACLC"
let pmset="/usr/bin/pmset"
/// Runs a fixed program with argv (no shell). Returns the exit code and standard output.
func run(_ path:String,_ arguments:[String]) -> (Int32,String)? {
    let p=Process();p.executableURL=URL(fileURLWithPath:path);p.arguments=arguments
    let out=Pipe();p.standardOutput=out;p.standardError=FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    let data=out.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit()
    return (p.terminationStatus,String(decoding:data,as:UTF8.self))
}
final class Service:NSObject,ChargeHelperProtocol {
    let domain=TopoffDomain.name as CFString
    func value(_ key:String) -> CFPropertyList? { CFPreferencesCopyValue(key as CFString,domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost) }
    func setLimit(_ percent:Int,reply:@escaping (String?)->Void) {
        guard let writes=TopoffDomain.writes(limit:percent,existingFeature:value(TopoffDomain.featureKey)) else { return reply(HelperReply.limitOutOfRange.rawValue) }
        for (key,v) in writes { CFPreferencesSetValue(key as CFString,v as CFPropertyList,domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost) }
        guard CFPreferencesSynchronize(domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost) else { return reply(HelperReply.limitSaveFailed.rawValue) }
        _=vb_notify(TopoffDomain.notification)
        reply(nil)
    }
    func readState(reply:@escaping ([String:String])->Void) {
        var r:[String:String]=[:]
        for key in [TopoffDomain.limitKey,TopoffDomain.featureKey] { r[key]=value(key).map { "\($0)" } ?? "none" }
        reply(r)
    }
    func version(reply:@escaping (Int)->Void) { reply(HelperPolicy.protocolVersion) }
    func setLowPowerMode(_ on:Bool,reply:@escaping (String?)->Void) {
        guard let (code,text)=run(pmset,["-g","custom"]),code==0 else { return reply(HelperReply.lowPowerReadFailed.rawValue) }
        guard let arguments=LowPowerSettings.parse(text).arguments(on:on) else { return reply(HelperReply.lowPowerMissing.rawValue) }
        guard let (status,_)=run(pmset,arguments),status==0 else { return reply(HelperReply.lowPowerFailed.rawValue) }
        reply(nil)
    }
    func setMagSafeLED(_ raw:Int,reply:@escaping (String?)->Void) {
        guard let led=MagSafeLED(rawValue:raw) else { return reply(HelperReply.ledValueRejected.rawValue) }
        let r=vb_smc_write_aclc(UInt8(led.rawValue))
        reply(r==0 ? nil:r==VB_SMC_UNSUPPORTED ? HelperReply.ledUnsupported.rawValue:HelperReply.ledFailed.rawValue)
    }
}
/// Root-only test command, used when the binary is started by hand (launchd passes no arguments).
/// `--led read|system|off|green|orange`: prints the previous value and, for writes, the value written (no read-back: the key shows the displayed color).
/// Exit codes: 0 ok, 1 failure, 2 usage.
func ledCommand(_ args:[String]) -> Int32 {
    func fail(_ text:String,_ code:Int32) -> Int32 { FileHandle.standardError.write((text+"\n").data(using:.utf8)!);return code }
    let names=["system":MagSafeLED.system,"off":.off,"green":.green,"orange":.orange]
    guard args.count==2,args[0]=="--led",args[1]=="read"||names[args[1]] != nil else {
        return fail(tr("Usage: \(CommandLine.arguments[0]) --led read|system|off|green|orange","사용법: \(CommandLine.arguments[0]) --led read|system|off|green|orange"),2)
    }
    guard getuid()==0 else { return fail(tr("Administrator rights are required: sudo \(CommandLine.arguments[0]) --led \(args[1])","관리자 권한이 필요합니다: sudo \(CommandLine.arguments[0]) --led \(args[1])"),1) }
    var old:UInt8=0
    let r=vb_smc_read_u8(ledKey,&old)
    guard r==0 else { return fail(tr("Could not read \(ledKey). (\(r))","\(ledKey) 값을 읽지 못했습니다. (\(r))"),1) }
    guard let led=names[args[1]] else { print(tr("\(ledKey) previous value \(old)","\(ledKey) 이전 값 \(old)"));return 0 }
    let w=vb_smc_write_aclc(UInt8(led.rawValue))
    guard w==0 else { return fail(tr("\(ledKey) previous value \(old) · could not write. (\(w))","\(ledKey) 이전 값 \(old) · 쓰지 못했습니다. (\(w))"),1) }
    // The key reads the LED's displayed color, not the control mode, so a read-back proves nothing.
    print(tr("\(ledKey) previous value \(old) → wrote \(led.rawValue)","\(ledKey) 이전 값 \(old) → \(led.rawValue) 썼습니다"))
    return 0
}
let cliArguments=Array(CommandLine.arguments.dropFirst())
if !cliArguments.isEmpty { exit(ledCommand(cliArguments)) }
final class Gate:NSObject,NSXPCListenerDelegate {
    func listener(_ listener:NSXPCListener,shouldAcceptNewConnection c:NSXPCConnection) -> Bool {
        var console:uid_t=0
        let user=SCDynamicStoreCopyConsoleUser(nil,&console,nil)
        var buffer=[CChar](repeating:0,count:4096)
        let path=vb_pid_path(c.processIdentifier,&buffer,Int32(buffer.count))==0 ? String(cString:buffer):nil
        guard HelperPolicy.allows(clientUID:c.effectiveUserIdentifier,consoleUID:user==nil ? nil:console,clientPath:path) else { return false }
        // The signature check is enforced by XPC on every message, so a PID swap after the path check fails.
        c.setCodeSigningRequirement(clientRequirement)
        c.exportedInterface=NSXPCInterface(with:ChargeHelperProtocol.self)
        c.exportedObject=Service()
        c.resume();return true
    }
}
/// Official builds carry a team ID, and only a client signed by the same team is accepted.
/// An unreadable signature must not fall back to identifier-only, so the helper exits and launchd retries.
let signing=CodeSigningIdentity.own
switch signing {
case .unknown(let status):NSLog("VibeBattery helper: cannot read own code signature (OSStatus %d), exiting",status);exit(1)
case .adHoc:NSLog("VibeBattery helper: self-built (ad-hoc), not team-pinned")
case .team:break
}
let clientRequirement=HelperPolicy.clientRequirement(signing)
let gate=Gate()
let listener=NSXPCListener(machServiceName:HelperPolicy.label)
listener.delegate=gate;listener.resume()
RunLoop.main.run()
