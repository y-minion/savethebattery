import Foundation
public struct ProcessIdentity: Codable, Equatable, Sendable {
    public var pid: Int32; public var uid: UInt32; public var started: UInt64
    public init(pid: Int32, uid: UInt32, started: UInt64) { self.pid=pid; self.uid=uid; self.started=started }
    public func canTerminate(current: ProcessIdentity?, user: UInt32, name: String) -> Bool {
        let protected: Set<String> = ["launchd","kernel_task","loginwindow","WindowServer","zsh","bash","sh","fish","login","sshd","Terminal","iTerm2","iTerm","ghostty","Ghostty","VibeBattery","vibebattery"]
        return pid > 1 && uid == user && current == self && !protected.contains(name)
    }
}
