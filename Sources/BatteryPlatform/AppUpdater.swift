import Foundation
import CryptoKit
import Security
import BatteryCore
/// Update now: download the release zip, check it, and put it in Applications. The running app is untouched until the swap.
public enum AppUpdater {
    public enum Failure: Error, LocalizedError {
        case noAssets, download, tooLarge, checksum, archive, signature, version
        public var errorDescription:String? {
            switch self {
            case .noAssets:return tr("The release has no app download.","릴리스에 앱 파일이 없습니다.")
            case .download:return tr("The download failed. Check the connection and try again.","내려받지 못했습니다. 연결을 확인하고 다시 시도하세요.")
            case .tooLarge:return tr("The download is larger than expected.","내려받는 파일이 예상보다 큽니다.")
            case .checksum:return tr("The download does not match its checksum.","내려받은 파일의 체크섬이 맞지 않습니다.")
            case .archive:return tr("The download does not contain the app.","내려받은 파일에 앱이 없습니다.")
            case .signature:return tr("The new app is not signed by the same team as this one.","새 앱이 지금 앱과 같은 팀으로 서명되어 있지 않습니다.")
            case .version:return tr("The new app is not the announced newer version.","새 앱이 안내된 새 버전이 아닙니다.")
            }
        }
    }
    /// Swaps the verified release in at Applications. Returns what the relauncher removes after the restart.
    public static func install(_ release:LatestRelease,current:String,team:String) async throws -> [URL] {
        guard let a=AppUpdate.assets(release.assets,allowFileURLs:ReleaseClient.testFeed != nil) else { throw Failure.noAssets }
        let fm=FileManager.default
        let work=fm.temporaryDirectory.appendingPathComponent("savethebattery-update-\(UUID().uuidString)")
        try fm.createDirectory(at:work,withIntermediateDirectories:true)
        do {
            let zip=work.appendingPathComponent(AppUpdate.zipName),sum=work.appendingPathComponent(AppUpdate.checksumName)
            do { try await ReleaseClient.download(a.zip,to:zip,limit:AppUpdate.maxZipBytes);try await ReleaseClient.download(a.checksum,to:sum,limit:4096) }
            catch let e as Failure { throw e } catch { throw Failure.download }
            let size=(try? fm.attributesOfItem(atPath:zip.path)[.size] as? NSNumber)?.intValue ?? .max
            guard size<=AppUpdate.maxZipBytes else { throw Failure.tooLarge }
            guard let want=AppUpdate.digest(fromChecksumFile:(try? String(contentsOf:sum,encoding:.utf8)) ?? ""),
                  let data=try? Data(contentsOf:zip),SHA256.hash(data:data).map({ String(format:"%02x",$0) }).joined()==want else { throw Failure.checksum }
            let out=work.appendingPathComponent("x");try fm.createDirectory(at:out,withIntermediateDirectories:true)
            let name=(HelperPolicy.appPath as NSString).lastPathComponent
            guard BundleSwap.run("/usr/bin/ditto",["-x","-k",zip.path,out.path]),(try? fm.contentsOfDirectory(atPath:out.path))==[name] else { throw Failure.archive }
            let app=out.appendingPathComponent(name)
            guard signedByTeam(app,team:team) else { throw Failure.signature }
            guard let v=NSDictionary(contentsOf:app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String,
                  AppUpdate.acceptsVersion(bundle:v,tag:release.tag,current:current) else { throw Failure.version }
            let old=try BundleSwap.install(app,at:URL(fileURLWithPath:HelperPolicy.appPath))
            return (old.map { [$0] } ?? [])+[work]
        } catch { try? fm.removeItem(at:work);throw error }
    }
    /// The same requirement the helper places on its clients: this bundle ID, an Apple anchor and this team, checked over every architecture and nested tool.
    static func signedByTeam(_ app:URL,team:String) -> Bool {
        var code:SecStaticCode?,req:SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL,[],&code)==errSecSuccess,let code,
              SecRequirementCreateWithString(HelperPolicy.clientRequirement(.team(team)) as CFString,[],&req)==errSecSuccess,let req else { return false }
        return SecStaticCodeCheckValidity(code,SecCSFlags(rawValue:kSecCSStrictValidate|kSecCSCheckAllArchitectures|kSecCSCheckNestedCode),req)==errSecSuccess
    }
}
