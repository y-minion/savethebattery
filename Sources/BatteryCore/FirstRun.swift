import Foundation
/// What the first-run cards offer.
public enum FirstRun {
    /// The helper and updates only work for the copy in Applications.
    public static func needsMove(bundlePath:String) -> Bool { (bundlePath as NSString).standardizingPath != HelperPolicy.appPath }
    /// After a move the original goes to the Trash, unless it is on a read-only volume such as the disk image.
    public static func trashesOriginal(path:String,readOnlyVolume:Bool) -> Bool {
        !readOnlyVolume && (path as NSString).standardizingPath != HelperPolicy.appPath
    }
    /// macOS can set a limit, nothing else manages charging, and no limit below 100% is in force.
    public static func suggestsLimit(_ s:ChargeLimitState,conflicts:Bool,dismissed:Bool) -> Bool {
        guard s.supported==true,!conflicts,!dismissed else { return false }
        return s.enabled != true || (s.limit ?? 100) >= 100
    }
}
