import Testing
import Foundation
import BatteryCore
struct AppUpdateTests {
    let base="https://github.com/y-minion/savethebattery/releases/download/v0.2.1/"
    func asset(_ name:String,_ url:String) -> ReleaseAsset { ReleaseAsset(name:name,browser_download_url:url) }
    @Test func picksTheZipAndChecksumOfThisRepository() {
        let list=[asset("savethebattery.dmg",base+"savethebattery.dmg"),asset("savethebattery.zip",base+"savethebattery.zip"),asset("savethebattery.zip.sha256",base+"savethebattery.zip.sha256")]
        let a=AppUpdate.assets(list,allowFileURLs:false)
        #expect(a?.zip.absoluteString==base+"savethebattery.zip")
        #expect(a?.checksum.absoluteString==base+"savethebattery.zip.sha256")
    }
    @Test func refusesAssetsFromElsewhere() {
        let ok=asset("savethebattery.zip.sha256",base+"savethebattery.zip.sha256")
        for bad in ["https://github.com/other/repo/releases/download/v1/savethebattery.zip",
                    "http://github.com/y-minion/savethebattery/releases/download/v0.2.1/savethebattery.zip",
                    "https://github.com.evil.com/y-minion/savethebattery/releases/download/v0.2.1/savethebattery.zip",
                    "https://github.com/y-minion/savethebattery/archive/savethebattery.zip",
                    "file:///tmp/savethebattery.zip"] {
            #expect(AppUpdate.assets([asset("savethebattery.zip",bad),ok],allowFileURLs:false)==nil)
        }
        #expect(AppUpdate.assets([ok],allowFileURLs:false)==nil)
        #expect(AppUpdate.assets([],allowFileURLs:false)==nil)
    }
    @Test func aLocalTestFeedMayUseFileURLs() {
        let list=[asset("savethebattery.zip","file:///tmp/r/savethebattery.zip"),asset("savethebattery.zip.sha256","file:///tmp/r/savethebattery.zip.sha256")]
        #expect(AppUpdate.assets(list,allowFileURLs:true) != nil)
        #expect(AppUpdate.assets(list,allowFileURLs:false)==nil)
    }
    @Test func readsShasumOutput() {
        let hex=String(repeating:"ab",count:32)
        #expect(AppUpdate.digest(fromChecksumFile:"\(hex)  savethebattery.zip\n")==hex)
        #expect(AppUpdate.digest(fromChecksumFile:hex.uppercased())==hex)
        #expect(AppUpdate.digest(fromChecksumFile:"\(hex) *savethebattery.zip")==hex)
        #expect(AppUpdate.digest(fromChecksumFile:"\(hex)  other.zip")==nil)
        #expect(AppUpdate.digest(fromChecksumFile:String(hex.dropLast()))==nil)
        #expect(AppUpdate.digest(fromChecksumFile:String(repeating:"zz",count:32))==nil)
        #expect(AppUpdate.digest(fromChecksumFile:"")==nil)
    }
    @Test func onlyTheAnnouncedNewerVersionIsAccepted() {
        #expect(AppUpdate.acceptsVersion(bundle:"0.2.1",tag:"v0.2.1",current:"0.2.0"))
        #expect(!AppUpdate.acceptsVersion(bundle:"0.2.0",tag:"v0.2.1",current:"0.2.0"))
        #expect(!AppUpdate.acceptsVersion(bundle:"0.2.0",tag:"v0.2.0",current:"0.2.0"))
        #expect(!AppUpdate.acceptsVersion(bundle:"0.1.9",tag:"v0.1.9",current:"0.2.0"))
        #expect(!AppUpdate.acceptsVersion(bundle:"junk",tag:"v0.2.1",current:"0.2.0"))
    }
    @Test func updateNeedsTheTeamSignedApplicationsCopy() {
        AppLanguage.$forced.withValue(.en) {
            #expect(AppUpdate.unavailableReason(bundlePath:"/Applications/Save the Battery.app",signing:.team("JQWWU7443A"),applicationsWritable:true)==nil)
            #expect(AppUpdate.unavailableReason(bundlePath:"/Users/u/Downloads/Save the Battery.app",signing:.team("JQWWU7443A"),applicationsWritable:true)?.contains("Applications")==true)
            #expect(AppUpdate.unavailableReason(bundlePath:"/Applications/Save the Battery.app",signing:.adHoc,applicationsWritable:true)?.contains("self-built")==true)
            #expect(AppUpdate.unavailableReason(bundlePath:"/Applications/Save the Battery.app",signing:.unknown(-1),applicationsWritable:true) != nil)
            #expect(AppUpdate.unavailableReason(bundlePath:"/Applications/Save the Battery.app",signing:.team("JQWWU7443A"),applicationsWritable:false)?.contains("administrator")==true)
        }
    }
    @Test func releaseJSONDecodesWithAssets() throws {
        let json=#"{"tag_name":"v0.2.1","html_url":"https://github.com/y-minion/savethebattery/releases/tag/v0.2.1","assets":[{"name":"savethebattery.zip","browser_download_url":"\#(base)savethebattery.zip","size":1}]}"#
        let r=try JSONDecoder().decode(LatestRelease.self,from:Data(json.utf8))
        #expect(r.tag=="v0.2.1");#expect(r.assets.count==1)
        let bare=try JSONDecoder().decode(LatestRelease.self,from:Data(#"{"tag_name":"v0.2.1","html_url":"https://github.com/y-minion/savethebattery/releases/tag/v0.2.1"}"#.utf8))
        #expect(bare.assets.isEmpty)
    }
}
