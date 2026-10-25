import Foundation
import SystemConfiguration
import BatteryCore
import BatteryPlatform
import MacBridge
// Root daemon. Accepts only fixed requests (a bounded limit write, a state read, the
// protocol version, Low Power Mode on/off and an allow-listed MagSafe LED value) from the
// console user's /Applications/VibeBattery.app; no generic defaults, keys or commands.
/// The only SMC key the helper writes. Never taken from a request or an argument.
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
    func version(reply:@escaping (Int)->Void) { reply(HelperPolicy.protocolVersion) }
    func setLowPowerMode(_ on:Bool,reply:@escaping (String?)->Void) {
        guard let (code,text)=run(pmset,["-g","custom"]),code==0 else { return reply("저전력 모드 설정을 읽지 못했습니다.") }
        guard let arguments=LowPowerSettings.parse(text).arguments(on:on) else { return reply("이 맥에서 저전력 모드 설정을 찾지 못했습니다.") }
        guard let (status,_)=run(pmset,arguments),status==0 else { return reply("저전력 모드를 바꾸지 못했습니다.") }
        reply(nil)
    }
    func setMagSafeLED(_ raw:Int,reply:@escaping (String?)->Void) {
        guard let led=MagSafeLED(rawValue:raw) else { return reply("허용되지 않은 LED 값입니다.") }
        let r=vb_smc_write_u8(ledKey,UInt8(led.rawValue))
        reply(r==0 ? nil:"MagSafe LED를 바꾸지 못했습니다. (\(r))")
    }
}
/// Root-only test command, used when the binary is started by hand (launchd passes no arguments).
/// `--led read|system|off|green|orange`: prints the previous value and, for writes, the value written (no read-back: the key shows the displayed color).
/// Exit codes: 0 ok, 1 failure, 2 usage.
func ledCommand(_ args:[String]) -> Int32 {
    func fail(_ text:String,_ code:Int32) -> Int32 { FileHandle.standardError.write((text+"\n").data(using:.utf8)!);return code }
    let names=["system":MagSafeLED.system,"off":.off,"green":.green,"orange":.orange]
    guard args.count==2,args[0]=="--led",args[1]=="read"||names[args[1]] != nil else {
        return fail("사용법: \(CommandLine.arguments[0]) --led read|system|off|green|orange",2)
    }
    guard getuid()==0 else { return fail("관리자 권한이 필요합니다: sudo \(CommandLine.arguments[0]) --led \(args[1])",1) }
    var old:UInt8=0
    let r=vb_smc_read_u8(ledKey,&old)
    guard r==0 else { return fail("\(ledKey) 값을 읽지 못했습니다. (\(r))",1) }
    guard let led=names[args[1]] else { print("\(ledKey) 이전 값 \(old)");return 0 }
    let w=vb_smc_write_u8(ledKey,UInt8(led.rawValue))
    guard w==0 else { return fail("\(ledKey) 이전 값 \(old) · 쓰지 못했습니다. (\(w))",1) }
    // The key reads the LED's displayed color, not the control mode, so a read-back proves nothing.
    print("\(ledKey) 이전 값 \(old) → \(led.rawValue) 썼습니다")
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
