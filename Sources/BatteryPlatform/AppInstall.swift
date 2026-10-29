import Foundation
import BatteryCore
/// Puts a new copy of the app in place for Move to Applications and the in-app update.
public enum BundleSwap {
    public enum Failure: Error, LocalizedError {
        case copy, swap(String)
        public var errorDescription:String? {
            switch self {
            case .copy:return tr("Could not copy the app.","앱을 복사하지 못했습니다.")
            case .swap(let why):return tr("Could not put the app in place: \(why)","앱을 제자리에 넣지 못했습니다: \(why)")
            }
        }
    }
    /// Copies `source` next to `destination`, then swaps it in; the previous copy stays aside until the caller removes it.
    /// The quarantine flag is dropped from the copy: the user already chose to run this app, and the flag would make macOS
    /// run the moved copy from a random read-only path again. Returns where the previous copy went, nil when there was none.
    /// On failure the previous copy is back in place and nothing staged is left.
    public static func install(_ source:URL,at destination:URL) throws -> URL? {
        let fm=FileManager.default,dir=destination.deletingLastPathComponent(),name=destination.lastPathComponent
        let staged=dir.appendingPathComponent(".\(name).new"),old=dir.appendingPathComponent(".\(name).old")
        try? fm.removeItem(at:staged);try? fm.removeItem(at:old)
        guard fm.fileExists(atPath:source.path),run("/usr/bin/ditto",[source.path,staged.path]) else { try? fm.removeItem(at:staged);throw Failure.copy }
        _=run("/usr/bin/xattr",["-d","-r","com.apple.quarantine",staged.path])
        var moved:URL?
        if fm.fileExists(atPath:destination.path) {
            do { try fm.moveItem(at:destination,to:old);moved=old }
            catch { try? fm.removeItem(at:staged);throw Failure.swap(error.localizedDescription) }
        }
        do { try fm.moveItem(at:staged,to:destination) }
        catch {
            if let moved { try? fm.moveItem(at:moved,to:destination) }
            try? fm.removeItem(at:staged);throw Failure.swap(error.localizedDescription)
        }
        return moved
    }
    static func run(_ tool:String,_ args:[String]) -> Bool {
        let p=Process();p.executableURL=URL(fileURLWithPath:tool);p.arguments=args
        p.standardOutput=FileHandle.nullDevice;p.standardError=FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit();return p.terminationStatus==0
    }
}
/// Starts the new copy after this process has quit.
public enum Relauncher {
    /// Waits for `pid` to exit (at most a minute), opens `app`, then deletes `cleanup`. The caller quits right after.
    /// Paths go in as arguments, never into the script text.
    public static func openAfterExit(_ app:URL,removing cleanup:[URL],pid:Int32=getpid(),opener:String="/usr/bin/open") throws {
        let script=#"pid=$1;opener=$2;app=$3;shift 3;i=0;while kill -0 "$pid" 2>/dev/null && [ $i -lt 300 ];do sleep 0.2;i=$((i+1));done;"$opener" "$app";for p in "$@";do /bin/rm -rf "$p";done"#
        let p=Process();p.executableURL=URL(fileURLWithPath:"/bin/sh")
        p.arguments=["-c",script,"relaunch",String(pid),opener,app.path]+cleanup.map(\.path)
        p.standardInput=FileHandle.nullDevice;p.standardOutput=FileHandle.nullDevice;p.standardError=FileHandle.nullDevice
        try p.run()
    }
}
/// Where the running copy really is, for Move to Applications.
public enum AppLocation {
    /// A quarantined app opened where it was downloaded runs from a random read-only App Translocation path;
    /// Security.framework maps it back. Without that function the bundle path is used.
    public static func original(_ bundle:URL=Bundle.main.bundleURL) -> URL {
        typealias OriginalPath=@convention(c) (CFURL,UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard bundle.path.contains("/AppTranslocation/"),
              let h=dlopen("/System/Library/Frameworks/Security.framework/Security",RTLD_LAZY),
              let sym=dlsym(h,"SecTranslocateCreateOriginalPathForURL") else { return bundle }
        let f=unsafeBitCast(sym,to:OriginalPath.self)
        return f(bundle as CFURL,nil)?.takeRetainedValue() as URL? ?? bundle
    }
    /// Unknown counts as read-only, so an unreadable location is never trashed.
    public static func onReadOnlyVolume(_ url:URL) -> Bool { (try? url.resourceValues(forKeys:[.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? true }
    public static var applicationsWritable:Bool { FileManager.default.isWritableFile(atPath:"/Applications") }
}
