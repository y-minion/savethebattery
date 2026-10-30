import Foundation
import BatteryCore
/// The app's only network requests: the latest GitHub release, and that release's zip when the user clicks Update now. Nothing identifying is sent.
public struct ReleaseClient {
    public static var bundleVersion:String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0" }
    /// `STB_RELEASE_FEED`: a local JSON file shaped like GitHub's answer, so the update can be tested on a device before a release.
    /// Its assets may be file URLs; the signature and version checks still apply.
    public static var testFeed:URL? {
        guard let s=ProcessInfo.processInfo.environment["STB_RELEASE_FEED"],!s.isEmpty else { return nil }
        return s.hasPrefix("file://") ? URL(string:s):URL(fileURLWithPath:s)
    }
    static var session:URLSession {
        let cfg=URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest=30;cfg.httpShouldSetCookies=false;cfg.httpCookieStorage=nil;cfg.urlCache=nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders=["User-Agent":"SaveTheBattery/\(bundleVersion)"]
        return URLSession(configuration:cfg)
    }
    public static func latest() async -> LatestRelease? {
        let data:Data
        if let feed=testFeed { guard let d=try? Data(contentsOf:feed) else { return nil };data=d }
        else {
            var req=URLRequest(url:URL(string:"https://api.github.com/repos/y-minion/savethebattery/releases/latest")!,timeoutInterval:10)
            req.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
            guard let (d,resp)=try? await session.data(for:req),(resp as? HTTPURLResponse)?.statusCode==200 else { return nil }
            data=d
        }
        guard let r=try? JSONDecoder().decode(LatestRelease.self,from:data),let url=URL(string:r.page),UpdateCheck.isTrustedReleaseURL(url) else { return nil }
        return r
    }
    /// Saves `url` at `destination`; `limit` bounds what the server announces and what arrives.
    static func download(_ url:URL,to destination:URL,limit:Int) async throws {
        if url.isFileURL { try FileManager.default.copyItem(at:url,to:destination);return }
        let (tmp,resp)=try await session.download(from:url)
        guard let http=resp as? HTTPURLResponse,http.statusCode==200 else { throw AppUpdater.Failure.download }
        guard resp.expectedContentLength<=Int64(limit) else { throw AppUpdater.Failure.tooLarge }
        try FileManager.default.moveItem(at:tmp,to:destination)
    }
}
