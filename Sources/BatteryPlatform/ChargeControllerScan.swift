import Foundation
import AppKit
import BatteryCore
public enum ChargeControllerScan {
    public static let directories=["/Library/LaunchDaemons","/Library/PrivilegedHelperTools"]
    public static func current() -> [OtherChargeController] {
        let ids=NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let items=directories.flatMap { d in ((try? FileManager.default.contentsOfDirectory(atPath:d)) ?? []).map { "\(d)/\($0)" } }
        return ChargeControllerDetector.detect(runningBundleIDs:ids,systemItems:items)
    }
}
