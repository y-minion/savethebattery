import Foundation
public struct OtherChargeController: Equatable, Sendable {
    public let name:String;public let evidence:String
    public init(name:String,evidence:String) { self.name=name;self.evidence=evidence }
}
public enum ChargeControllerDetector {
    // AlDente's identifiers were observed on the target Mac; the others come from
    // each project's public installer or Xcode project.
    private static let rules:[(name:String,prefixes:[String])]=[
        ("AlDente",["com.apphousekitchen.aldente"]),("batt",["cc.chlc.batt"]),
        ("battery",["co.palokaj.battery","battery.plist"]),
        ("Battery Toolkit",["me.mhaeuser.batterytoolkit","battery toolkit.app"])]
    public static func detect(runningBundleIDs:[String],systemItems:[String]) -> [OtherChargeController] {
        rules.compactMap { r -> OtherChargeController? in
            func matches(_ s:String) -> Bool { let s=s.lowercased();return r.prefixes.contains { s.hasPrefix($0) } }
            if let id=runningBundleIDs.first(where:matches) { return .init(name:r.name,evidence:tr("Running: \(id)","실행 중: \(id)")) }
            if let item=systemItems.first(where:{ matches(($0 as NSString).lastPathComponent) }) { return .init(name:r.name,evidence:tr("Installed: \(item)","설치됨: \(item)")) }
            return nil
        }
    }
}
