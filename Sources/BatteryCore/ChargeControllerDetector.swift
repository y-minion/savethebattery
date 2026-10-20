import Foundation
public struct OtherChargeController: Equatable, Sendable {
    public let name:String;public let evidence:String
    public init(name:String,evidence:String) { self.name=name;self.evidence=evidence }
}
public enum ChargeControllerDetector {
    // AlDente's identifiers were observed on the target Mac; batt's daemon label is from its public installer.
    private static let rules:[(name:String,prefix:String)]=[("AlDente","com.apphousekitchen.aldente"),("batt","cc.chlc.batt")]
    public static func detect(runningBundleIDs:[String],systemItems:[String]) -> [OtherChargeController] {
        rules.compactMap { r -> OtherChargeController? in
            if let id=runningBundleIDs.first(where:{ $0.lowercased().hasPrefix(r.prefix) }) { return .init(name:r.name,evidence:"실행 중: \(id)") }
            if let item=systemItems.first(where:{ ($0 as NSString).lastPathComponent.lowercased().hasPrefix(r.prefix) }) { return .init(name:r.name,evidence:"설치됨: \(item)") }
            return nil
        }
    }
}
