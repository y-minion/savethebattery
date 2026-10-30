import Foundation
import Security
import BatteryCore
public enum CodeSigningIdentity {
    /// This process's own signer, read once per process.
    public static let own:SigningTeam=read()
    private static func read() -> SigningTeam {
        var code:SecCode?
        var s=SecCodeCopySelf([],&code)
        guard s==errSecSuccess,let code else { return .unknown(s==errSecSuccess ? errSecInternalComponent:s) }
        var staticCode:SecStaticCode?
        s=SecCodeCopyStaticCode(code,[],&staticCode)
        guard s==errSecSuccess,let staticCode else { return .unknown(s==errSecSuccess ? errSecInternalComponent:s) }
        var info:CFDictionary?
        s=SecCodeCopySigningInformation(staticCode,SecCSFlags(rawValue:kSecCSSigningInformation),&info)
        guard s==errSecSuccess,let dict=info as? [String:Any] else { return .unknown(s==errSecSuccess ? errSecInternalComponent:s) }
        let certs=dict[kSecCodeInfoCertificates as String] as? [Any] ?? []
        return SigningTeam(status:s,team:dict[kSecCodeInfoTeamIdentifier as String] as? String,
                           flags:(dict[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value,hasCertificates:!certs.isEmpty)
    }
}
