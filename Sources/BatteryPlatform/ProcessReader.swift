import Foundation
import MacBridge
public struct ProcessSample: Identifiable, Sendable {
    public var identity: ProcessIdentity; public var name: String
    public var cpu: Double; public var memory: UInt64; public var cpuNS: UInt64
    public var id: Int32 { identity.pid }
}
public final class ProcessReader {
    private var previous: [Int32:(UInt64,UInt64)] = [:]
    private var previousTime: TimeInterval?
    public init() {}
    public static func one(_ pid: Int32) -> ProcessSample? {
        var raw=VBProcess(); guard vb_process(pid,&raw)==1 else { return nil }
        let name=withUnsafePointer(to:&raw.name) { $0.withMemoryRebound(to:CChar.self,capacity:64) { String(cString:$0) } }
        return ProcessSample(identity:.init(pid:pid,uid:raw.uid,started:raw.started),name:name,cpu:0,memory:raw.memory,cpuNS:raw.cpu_ns)
    }
    public func snapshot() -> [ProcessSample] {
        var pids=[Int32](repeating:0,count:32768)
        let count=pids.withUnsafeMutableBufferPointer { vb_pids($0.baseAddress,Int32($0.count)) }
        let now=ProcessInfo.processInfo.systemUptime; let elapsed=previousTime.map { now-$0 }
        var next:[Int32:(UInt64,UInt64)]=[:]; var result:[ProcessSample]=[]
        for pid in pids.prefix(Int(max(0,count))) where pid>1 {
            guard var s=Self.one(pid), s.identity.uid==geteuid() else { continue }
            next[pid]=(s.identity.started,s.cpuNS)
            if let old=previous[pid],old.0==s.identity.started,let elapsed,elapsed>0,s.cpuNS>=old.1 {
                s.cpu=Double(s.cpuNS-old.1)/1_000_000_000/elapsed*100
            }
            result.append(s)
        }
        previous=next;previousTime=now
        return result.sorted { $0.cpu>$1.cpu }
    }
    public static func terminate(_ sample: ProcessSample, force: Bool = false) throws {
        guard let current=one(sample.id), sample.identity.canTerminate(current:current.identity,user:geteuid(),name:current.name) else { throw PlatformError.message("프로세스가 변경되었거나 보호 대상입니다.") }
        let result=vb_signal(sample.id,sample.identity.started,force ? SIGKILL:SIGTERM)
        guard result==0 else { throw PlatformError.message("종료 요청 실패: \(String(cString:strerror(result)))") }
    }
}
public enum PlatformError: Error, LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let s)=self { return s }; return nil }
}
