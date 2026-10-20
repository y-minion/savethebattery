import Foundation
import AppKit
import BatteryCore
public enum ChargeControllerScan {
    public static var directories:[String] { ["/Library/LaunchDaemons","/Library/PrivilegedHelperTools","/Applications",NSHomeDirectory()+"/Library/LaunchAgents"] }
    public static func current() -> [OtherChargeController] {
        let ids=NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let items=directories.flatMap { d in ((try? FileManager.default.contentsOfDirectory(atPath:d)) ?? []).map { "\(d)/\($0)" } }
        return ChargeControllerDetector.detect(runningBundleIDs:ids,systemItems:items)
    }
}
