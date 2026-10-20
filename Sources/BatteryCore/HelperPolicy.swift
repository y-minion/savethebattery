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
    public static func allows(clientUID:UInt32,consoleUID:UInt32?,clientPath:String?) -> Bool {
        guard let consoleUID,consoleUID != 0,clientUID==consoleUID,let clientPath else { return false }
        return (clientPath as NSString).standardizingPath.hasPrefix(appPrefix)
    }
}
public enum TopoffDomain {
    public static let name="com.apple.smartcharging.topoffprotection"
    public static let limitKey="mclLimitValue",featureKey="MCLFeatureState"
    public static let notification="com.apple.smartcharging.defaultschanged"
    /// Keys to write for a limit. An existing feature state is left alone so an
    /// encoding we have not observed is never replaced.
    public static func writes(limit:Int,existingFeature:Any?) -> [String:Any]? {
        guard ChargeCommand.range.contains(limit) else { return nil }
        var w:[String:Any]=[limitKey:NSNumber(value:limit)]
        if existingFeature==nil { w[featureKey]=NSNumber(value:1) }
        return w
    }
}
