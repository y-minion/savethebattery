import Foundation
/// The app's only network request: the latest GitHub release tag and page. Nothing identifying is sent.
public struct ReleaseClient {
    struct Release:Decodable { let tag_name:String;let html_url:String }
    public static func latest() async -> (tag:String,url:URL)? {
        let cfg=URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest=10;cfg.httpShouldSetCookies=false;cfg.httpCookieStorage=nil;cfg.urlCache=nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        var req=URLRequest(url:URL(string:"https://api.github.com/repos/y-minion/vibebattery/releases/latest")!,timeoutInterval:10)
        req.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
        let v=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0"
        req.setValue("VibeBattery/\(v)",forHTTPHeaderField:"User-Agent")
        guard let (data,resp)=try? await URLSession(configuration:cfg).data(for:req),
              (resp as? HTTPURLResponse)?.statusCode==200,
              let r=try? JSONDecoder().decode(Release.self,from:data),
              let url=URL(string:r.html_url),url.scheme=="https" else { return nil }
        return (r.tag_name,url)
    }
}
