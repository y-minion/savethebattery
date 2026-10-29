import Foundation
public enum HelperPolicy {
    public static let label="io.github.y-minion.savethebattery.helper"
    public static let appIdentifier="io.github.y-minion.savethebattery"
    public static let helperIdentifier="io.github.y-minion.savethebattery.helper"
    /// Code signing requirement for a peer. With a team it must also be Apple-anchored and signed by that team;
    /// ad-hoc builds have no team, so they pin only the identifier. An unreadable signature matches nothing.
    public static func requirement(identifier:String,signing:SigningTeam) -> String {
        switch signing {
        case .team(let team):return "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        case .adHoc:return "identifier \"\(identifier)\""
        case .unknown:return "identifier \"\(identifier)\" and never"
        }
    }
    /// What the helper demands of the app.
    public static func clientRequirement(_ signing:SigningTeam) -> String { requirement(identifier:appIdentifier,signing:signing) }
    /// What the app demands of the helper.
    public static func helperRequirement(_ signing:SigningTeam) -> String { requirement(identifier:helperIdentifier,signing:signing) }
    public static let appPrefix="/Applications/Save the Battery.app/"
    public static let daemonPlist="/Library/LaunchDaemons/io.github.y-minion.savethebattery.helper.plist"
    /// 1: setLimit and readState. 2: adds version, setLowPowerMode and setMagSafeLED. 3: replies are `HelperReply` codes and the helper is team-pinned.
    public static let protocolVersion=3
    public static func allows(clientUID:UInt32,consoleUID:UInt32?,clientPath:String?) -> Bool {
        guard let consoleUID,consoleUID != 0,clientUID==consoleUID,let clientPath else { return false }
        return (clientPath as NSString).standardizingPath.hasPrefix(appPrefix)
    }
}
public enum HelperStatus: Equatable, Sendable {
    /// `outdated`: a helper that predates the current protocol; it still sets limits, but the app asks for a reinstall.
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
    /// Confirmation after the install or remove script exits 0; nil when the helper is not in the state the script was for.
    public func confirmation(afterInstall install:Bool) -> String? {
        switch (install,self) {
        case (true,.ready):return tr("The helper is installed and ready.","헬퍼를 설치했습니다. 바로 사용할 수 있습니다.")
        case (false,.notInstalled):return tr("The helper is removed.","헬퍼를 제거했습니다.")
        default:return nil
        }
    }
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
