import Foundation
import Security
public enum CodeSigningIdentity {
    /// The team ID in this process's own code signature; nil for ad-hoc or unsigned processes.
    public static func ownTeamID() -> String? {
        var code:SecCode?
        guard SecCodeCopySelf([],&code) == errSecSuccess,let code else { return nil }
        var staticCode:SecStaticCode?
        guard SecCodeCopyStaticCode(code,[],&staticCode) == errSecSuccess,let staticCode else { return nil }
        var info:CFDictionary?
        guard SecCodeCopySigningInformation(staticCode,SecCSFlags(rawValue:kSecCSSigningInformation),&info) == errSecSuccess,
              let dict=info as? [String:Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
