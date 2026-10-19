import Foundation
import AppKit
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
        // Capture the application instance before rechecking process identity. AppKit
        // addresses that instance even if its process exits; no raw PID signal here.
        guard let app=NSRunningApplication(processIdentifier:sample.id),
              let current=one(sample.id),sample.identity.canTerminate(current:current.identity,user:geteuid(),name:current.name),
              !app.isTerminated else { throw PlatformError.message("앱이 변경되었거나 보호 대상입니다. 일반 백그라운드 프로세스는 활성 상태 보기에서 확인하세요.") }
        guard force ? app.forceTerminate():app.terminate() else { throw PlatformError.message("앱이 종료 요청을 수락하지 않았습니다.") }
    }
    public static func canRequestTermination(_ sample:ProcessSample) -> Bool {
        sample.identity.canTerminate(current:sample.identity,user:geteuid(),name:sample.name) && NSRunningApplication(processIdentifier:sample.id) != nil
    }
}
public enum PlatformError: Error, LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let s)=self { return s }; return nil }
}
