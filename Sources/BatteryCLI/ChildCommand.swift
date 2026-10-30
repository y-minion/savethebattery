import Foundation
import MacBridge
import BatteryCore
import BatteryPlatform
final class ChildCommand {
    let pid:Int32
    let identity:ProcessIdentity?
    init(_ command:[String],environment:[String:String]) throws {
        let args=command.map { strdup($0) }+[nil]
        let env=environment.map { strdup("\($0.key)=\($0.value)") }+[nil]
        defer { args.forEach { free($0) };env.forEach { free($0) } }
        var child:Int32=0
        let status=args.withUnsafeBufferPointer { a in env.withUnsafeBufferPointer { e in vb_spawn(a.baseAddress,e.baseAddress,&child) } }
        guard status==0 else { throw PlatformError.message(tr("Could not start the command: \(String(cString:strerror(status)))","실행 실패: \(String(cString:strerror(status)))")) }
        pid=child;identity=ProcessReader.one(child)?.identity
    }
    func exitStatus() throws -> Int32? {
        var status:Int32=0;let result=vb_wait(pid,&status)
        if result<0 { throw PlatformError.message(tr("Could not read the command's exit status.","작업 종료 상태를 읽지 못했습니다.")) }
        return result==1 ? status:nil
    }
    func signal(_ number:Int32) {
        guard let identity else { return }
        _=vb_signal(pid,identity.started,number)
    }
}
func note(_ text:String) { FileHandle.standardError.write(Data(("[Save the Battery] "+text+"\n").utf8)) }
