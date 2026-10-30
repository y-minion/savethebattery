import Foundation
public struct ReleaseAsset: Decodable, Equatable, Sendable {
    public let name:String;public let browser_download_url:String
    public init(name:String,browser_download_url:String) { self.name=name;self.browser_download_url=browser_download_url }
}
/// The fields of GitHub's "latest release" answer the app uses.
public struct LatestRelease: Decodable, Sendable {
    public let tag:String;public let page:String;public let assets:[ReleaseAsset]
    enum CodingKeys:String,CodingKey { case tag="tag_name",page="html_url",assets }
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        tag=try c.decode(String.self,forKey:.tag);page=try c.decode(String.self,forKey:.page)
        assets=(try? c.decodeIfPresent([ReleaseAsset].self,forKey:.assets)) ?? []
    }
}
/// Rules for the in-app update. Integrity rests on the checksum and, above all, on the new app's team signature.
public enum AppUpdate {
    public static let zipName="savethebattery.zip",checksumName="savethebattery.zip.sha256"
    public static let maxZipBytes=200*1024*1024
    static let downloadPrefix="/y-minion/savethebattery/releases/download/"
    /// The zip and its checksum, both from this repository's release downloads. A local test feed may use file URLs.
    public static func assets(_ list:[ReleaseAsset],allowFileURLs:Bool) -> (zip:URL,checksum:URL)? {
        func url(_ name:String) -> URL? {
            guard let a=list.first(where:{ $0.name==name }),let u=URL(string:a.browser_download_url) else { return nil }
            if allowFileURLs && u.isFileURL { return u }
            return u.scheme=="https" && u.host?.lowercased()=="github.com" && u.path.hasPrefix(downloadPrefix) ? u:nil
        }
        guard let zip=url(zipName),let sum=url(checksumName) else { return nil }
        return (zip,sum)
    }
    /// The lowercase hex digest from `shasum -a 256` output: 64 hex digits, then optionally the zip's name.
    public static func digest(fromChecksumFile text:String) -> String? {
        let parts=text.split(whereSeparator:\.isWhitespace)
        guard let first=parts.first,first.count==64,first.allSatisfy(\.isHexDigit) else { return nil }
        if parts.count>1 && !(parts.count==2 && (parts[1]==zipName || parts[1]=="*"+zipName)) { return nil }
        return first.lowercased()
    }
    /// The downloaded app must be the announced release and newer than the running one: no downgrade, no replay.
    public static func acceptsVersion(bundle:String,tag:String,current:String) -> Bool {
        guard let b=SemVer(bundle),let t=SemVer(tag),b==t else { return false }
        return UpdateCheck.newer(latestTag:tag,current:current) != nil
    }
    /// Why Update now cannot run; nil when it can.
    public static func unavailableReason(bundlePath:String,signing:SigningTeam,applicationsWritable:Bool) -> String? {
        if FirstRun.needsMove(bundlePath:bundlePath) { return tr("Updates install into the Applications folder. Move the app there first.","업데이트는 응용 프로그램 폴더에 설치됩니다. 먼저 앱을 그곳으로 옮기세요.") }
        guard case .team=signing else { return tr("This is a self-built copy, so it cannot check that an update comes from the official team. Update it from Terminal instead.","직접 빌드한 사본이라 업데이트가 공식 팀에서 왔는지 확인할 수 없습니다. 터미널로 업데이트하세요.") }
        if !applicationsWritable { return tr("This account cannot write to Applications. Update from an administrator account or with Terminal.","이 계정은 응용 프로그램 폴더에 쓸 수 없습니다. 관리자 계정이나 터미널로 업데이트하세요.") }
        return nil
    }
}
