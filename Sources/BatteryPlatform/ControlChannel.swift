import Foundation
import Darwin
import BatteryCore
/// Same-user Unix socket through which `stb` asks the running app to change the charge limit.
/// The app stays the only writer, so the helper, the write log and change detection keep working.
public final class ControlServer {
    public static let maxLine=1024
    public static let readTimeout:TimeInterval=5
    private let path:URL;private let handler:(ChargeCommand)->ControlResponse;private let queue:DispatchQueue
    private var fd:Int32 = -1
    private let lock=NSLock();private var running=false
    /// The handler runs on the main queue, where the app's charge controller lives.
    public convenience init(path:URL,handler:@escaping (ChargeCommand)->ControlResponse) { self.init(path:path,handler:handler,queue:.main) }
    init(path:URL,handler:@escaping (ChargeCommand)->ControlResponse,queue:DispatchQueue) { self.path=path;self.handler=handler;self.queue=queue }
    public func start() throws {
        // A client that hangs up before the reply would otherwise end the whole app with SIGPIPE.
        signal(SIGPIPE,SIG_IGN)
        // A socket left by a crashed app would make bind fail.
        unlink(path.path)
        let s=socket(AF_UNIX,SOCK_STREAM,0)
        guard s>=0 else { throw POSIXError(.EIO) }
        guard var addr=ControlSocket.address(path) else { close(s);throw POSIXError(.ENAMETOOLONG) }
        let bound=withUnsafePointer(to:&addr) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { bind(s,$0,socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard bound==0,chmod(path.path,0o600)==0,listen(s,8)==0 else { close(s);unlink(path.path);throw POSIXError(.EACCES) }
        lock.lock();fd=s;running=true;lock.unlock()
        let t=Thread { [weak self] in self?.acceptLoop(s) }
        t.name="Save the Battery control";t.start()
    }
    public func stop() {
        lock.lock();let s=fd;let was=running;running=false;fd = -1;lock.unlock()
        guard was else { return }
        shutdown(s,SHUT_RDWR);close(s);unlink(path.path)
    }
    private var isRunning:Bool { lock.lock();defer { lock.unlock() };return running }
    private func acceptLoop(_ s:Int32) {
        while isRunning {
            let c=accept(s,nil,nil)
            if c<0 { if errno==EINTR { continue };break }
            serve(c);close(c)
        }
    }
    private func serve(_ c:Int32) {
        var uid=uid_t(0),gid=gid_t(0)
        guard getpeereid(c,&uid,&gid)==0,uid==getuid() else { return }
        // A client that hangs up early (a liveness check) must not kill the app with SIGPIPE.
        var nosig:Int32=1;setsockopt(c,SOL_SOCKET,SO_NOSIGPIPE,&nosig,socklen_t(MemoryLayout<Int32>.size))
        ControlSocket.setTimeout(c,SO_RCVTIMEO,Self.readTimeout);ControlSocket.setTimeout(c,SO_SNDTIMEO,Self.readTimeout)
        let response:ControlResponse
        if let line=ControlSocket.readLine(c,limit:Self.maxLine),let request=try? JSONDecoder().decode(ControlRequest.self,from:line),let command=request.chargeCommand() {
            response=queue.sync { handler(command) }
        } else {
            response=ControlResponse(ok:false,message:HelperReply.unsupportedRequest.rawValue,state:nil)
        }
        if let data=try? JSONEncoder().encode(response) { ControlSocket.writeAll(c,data+Data("\n".utf8)) }
    }
}
public enum ControlClient {
    public enum Failure: Error, Equatable { case notRunning, timedOut }
    public static func send(_ r:ControlRequest,path:URL,connectTimeout:TimeInterval=5,responseTimeout:TimeInterval=15) throws -> ControlResponse {
        let line=try JSONEncoder().encode(r)+Data("\n".utf8)
        return try exchange(line,path:path,connectTimeout:connectTimeout,responseTimeout:responseTimeout)
    }
    /// Whether an app is listening, for `stb charge status`.
    public static func isListening(path:URL) -> Bool {
        guard let s=try? connect(path:path,timeout:1) else { return false }
        close(s);return true
    }
    static func exchange(_ line:Data,path:URL,connectTimeout:TimeInterval,responseTimeout:TimeInterval) throws -> ControlResponse {
        let s=try connect(path:path,timeout:connectTimeout)
        defer { close(s) }
        ControlSocket.setTimeout(s,SO_SNDTIMEO,connectTimeout)
        guard ControlSocket.writeAll(s,line) else { throw Failure.notRunning }
        ControlSocket.setTimeout(s,SO_RCVTIMEO,responseTimeout)
        // No answer in time, a closed connection or an unreadable answer all leave the result unknown.
        guard let reply=ControlSocket.readLine(s,limit:64*1024),let r=try? JSONDecoder().decode(ControlResponse.self,from:reply) else { throw Failure.timedOut }
        return r
    }
    private static func connect(path:URL,timeout:TimeInterval) throws -> Int32 {
        guard var addr=ControlSocket.address(path) else { throw Failure.notRunning }
        let s=socket(AF_UNIX,SOCK_STREAM,0)
        guard s>=0 else { throw Failure.notRunning }
        var nosig:Int32=1;setsockopt(s,SOL_SOCKET,SO_NOSIGPIPE,&nosig,socklen_t(MemoryLayout<Int32>.size))
        let flags=fcntl(s,F_GETFL);_=fcntl(s,F_SETFL,flags|O_NONBLOCK)
        let r=withUnsafePointer(to:&addr) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.connect(s,$0,socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        if r != 0 {
            guard errno==EINPROGRESS || errno==EAGAIN else { close(s);throw Failure.notRunning }
            var p=pollfd(fd:s,events:Int16(POLLOUT),revents:0)
            var err:Int32=0;var len=socklen_t(MemoryLayout<Int32>.size)
            guard poll(&p,1,Int32(timeout*1000))==1,getsockopt(s,SOL_SOCKET,SO_ERROR,&err,&len)==0,err==0 else { close(s);throw Failure.notRunning }
        }
        _=fcntl(s,F_SETFL,flags)
        return s
    }
}
enum ControlSocket {
    static func address(_ path:URL) -> sockaddr_un? {
        var a=sockaddr_un();a.sun_family=sa_family_t(AF_UNIX)
        let bytes=Array(path.path.utf8)
        guard bytes.count<MemoryLayout.size(ofValue:a.sun_path) else { return nil }
        withUnsafeMutableBytes(of:&a.sun_path) { buf in for (i,b) in bytes.enumerated() { buf[i]=b } }
        return a
    }
    static func setTimeout(_ s:Int32,_ option:Int32,_ seconds:TimeInterval) {
        var tv=timeval(tv_sec:Int(seconds),tv_usec:Int32((seconds-Double(Int(seconds)))*1_000_000))
        setsockopt(s,SOL_SOCKET,option,&tv,socklen_t(MemoryLayout<timeval>.size))
    }
    /// Reads up to a newline; nil on timeout, close or a line longer than `limit`.
    static func readLine(_ s:Int32,limit:Int) -> Data? {
        var data=Data();var byte:UInt8=0
        while true {
            let n=read(s,&byte,1)
            if n<=0 { return nil }
            if byte==UInt8(ascii:"\n") { return data }
            data.append(byte)
            if data.count>limit { return nil }
        }
    }
    @discardableResult static func writeAll(_ s:Int32,_ data:Data) -> Bool {
        data.withUnsafeBytes { raw in
            var sent=0
            while sent<raw.count {
                let n=write(s,raw.baseAddress!+sent,raw.count-sent)
                if n<=0 { return false }
                sent+=n
            }
            return true
        }
    }
}
