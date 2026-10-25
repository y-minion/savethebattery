import Foundation
public enum HelperPolicy {
    public static let label="io.github.y-minion.vibebattery.helper"
    public static let appIdentifier="io.github.y-minion.vibebattery"
    // Ad-hoc builds have no team ID, so the requirement pins only the identifier.
    // Developer ID signing must add the team (spec section 8).
    public static let clientRequirement="identifier \"io.github.y-minion.vibebattery\""
    public static let helperRequirement="identifier \"io.github.y-minion.vibebattery.helper\""
    public static let appPrefix="/Applications/VibeBattery.app/"
    public static let daemonPlist="/Library/LaunchDaemons/io.github.y-minion.vibebattery.helper.plist"
    /// 1: setLimit and readState. 2: adds version, setLowPowerMode and setMagSafeLED.
    public static let protocolVersion=2
    public static func allows(clientUID:UInt32,consoleUID:UInt32?,clientPath:String?) -> Bool {
        guard let consoleUID,consoleUID != 0,clientUID==consoleUID,let clientPath else { return false }
        return (clientPath as NSString).standardizingPath.hasPrefix(appPrefix)
    }
}
public enum HelperStatus: Equatable, Sendable {
    /// `outdated`: an older helper that still sets limits but lacks the version 2 requests.
    case notInstalled, wrongLocation, unreachable, outdated, ready
    /// The helper only answers the app in /Applications, so probing from elsewhere would only fail.
    /// A helper without a version answer predates version 2.
    public static func evaluate(installed:Bool,appPath:String,probe:()->Bool,version:()->Int?={ HelperPolicy.protocolVersion }) -> HelperStatus {
        guard installed else { return .notInstalled }
        guard ((appPath as NSString).standardizingPath+"/").hasPrefix(HelperPolicy.appPrefix) else { return .wrongLocation }
        guard probe() else { return .unreachable }
        return (version() ?? 1)<HelperPolicy.protocolVersion ? .outdated:.ready
    }
    public var canSetLimit:Bool { self == .ready || self == .outdated }
}
/// MagSafe 3 LED values the helper may write. `init(rawValue:)` is the allow-list.
public enum MagSafeLED: Int, Codable, CaseIterable, Sendable {
    case system=0, off=1, green=3, orange=4
}
public enum TopoffDomain {
    public static let name="com.apple.smartcharging.topoffprotection"
    public static let limitKey="mclLimitValue",featureKey="MCLFeatureState"
    public static let notification="com.apple.smartcharging.defaultschanged"
    /// Keys to write for a limit. The feature state is set to 1 only when it is
    /// missing or the observed "off" value 0, so an unknown encoding is never replaced.
    public static func writes(limit:Int,existingFeature:Any?) -> [String:Any]? {
        guard ChargeCommand.range.contains(limit) else { return nil }
        var w:[String:Any]=[limitKey:NSNumber(value:limit)]
        if existingFeature==nil || (existingFeature as? NSNumber)?.intValue==0 { w[featureKey]=NSNumber(value:1) }
        return w
    }
}
