import Foundation
import BatteryCore
import IOKit.pwr_mgt
public final class PowerLease {
    private var assertion: IOPMAssertionID=0
    private var held=false
    public init() {}
    public func acquire(reason: String) throws {
        guard !held else { return }
        let status=IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,IOPMAssertionLevel(kIOPMAssertionLevelOn),reason as CFString,&assertion)
        guard status==kIOReturnSuccess else { throw PlatformError.message(tr("Keep-awake request failed (\(status))","작업 유지 요청 실패 (\(status))")) }
        held=true
    }
    public func release() { if held { IOPMAssertionRelease(assertion);held=false } }
    deinit { release() }
    public static func sleepDisplays() throws {
        let task=Process();task.executableURL=URL(fileURLWithPath:"/usr/bin/pmset");task.arguments=["displaysleepnow"]
        try task.run();task.waitUntilExit()
        guard task.terminationStatus==0 else { throw PlatformError.message(tr("Could not request display sleep.","디스플레이 잠자기를 요청하지 못했습니다.")) }
    }
}
