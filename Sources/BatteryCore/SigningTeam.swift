import Foundation
/// Who signed a process: an Apple team, nobody (ad-hoc or unsigned), or unknown because the signature could not be read.
public enum SigningTeam: Equatable, Sendable {
    case team(String), adHoc, unknown(OSStatus)
    /// `kSecCodeSignatureAdhoc` from the Security framework.
    public static let adhocFlag:UInt32=0x0002
    /// Maps a signing-information read. Only a successful read that shows no signer counts as ad-hoc;
    /// an error or a certificate-signed code without a team is unknown, so pinning fails closed.
    public init(status:OSStatus,team:String?,flags:UInt32?,hasCertificates:Bool) {
        guard status==0 else { self = .unknown(status);return }
        if let team { self = team.isEmpty ? .unknown(status):.team(team);return }
        if let flags,flags & Self.adhocFlag != 0 { self = .adHoc;return }
        self = hasCertificates ? .unknown(status):.adHoc
    }
}
