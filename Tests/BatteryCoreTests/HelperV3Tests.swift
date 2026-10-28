import Testing
import Foundation
@testable import BatteryCore
@testable import BatteryPlatform

struct HelperV3Tests {
    @Test func pinnedRequirement() {
        #expect(HelperPolicy.requirement(identifier:"io.github.y-minion.vibebattery",signing:.team("JQWWU7443A")) ==
          "identifier \"io.github.y-minion.vibebattery\" and anchor apple generic and certificate leaf[subject.OU] = \"JQWWU7443A\"")
        #expect(HelperPolicy.requirement(identifier:"io.github.y-minion.vibebattery",signing:.adHoc) == "identifier \"io.github.y-minion.vibebattery\"")
        #expect(HelperPolicy.clientRequirement(.adHoc) == "identifier \"io.github.y-minion.vibebattery\"")
        #expect(HelperPolicy.helperRequirement(.team("JQWWU7443A")).hasPrefix("identifier \"io.github.y-minion.vibebattery.helper\" and anchor apple generic"))
    }
    /// An unreadable signature must never fall back to identifier-only pinning.
    @Test func unknownSigningMatchesNothing() {
        #expect(HelperPolicy.helperRequirement(.unknown(-67050)) == "identifier \"io.github.y-minion.vibebattery.helper\" and never")
        #expect(HelperPolicy.clientRequirement(.unknown(0)).hasSuffix(" and never"))
    }
    @Test func signingTeamFromSignatureInfo() {
        let adhoc=SigningTeam.adhocFlag
        #expect(SigningTeam(status:0,team:"JQWWU7443A",flags:0,hasCertificates:true) == .team("JQWWU7443A"))
        #expect(SigningTeam(status:0,team:nil,flags:adhoc|0x20000,hasCertificates:false) == .adHoc)
        #expect(SigningTeam(status:0,team:nil,flags:nil,hasCertificates:false) == .adHoc)
        #expect(SigningTeam(status:0,team:nil,flags:0,hasCertificates:true) == .unknown(0))
        #expect(SigningTeam(status:-67050,team:nil,flags:adhoc,hasCertificates:false) == .unknown(-67050))
        #expect(SigningTeam(status:0,team:"",flags:0,hasCertificates:true) == .unknown(0))
    }
    @Test func replyCodesRoundTrip() {
        for r in HelperReply.allCases { #expect(HelperReply(rawValue:r.rawValue)==r); #expect(!r.text.isEmpty) }
        #expect(HelperReply.display("헬퍼가 예전 문장을 보냄") == "헬퍼가 예전 문장을 보냄")
        #expect(HelperReply.display(nil) == nil)
        AppLanguage.$forced.withValue(.en) { #expect(HelperReply.display("led.unsupported") == HelperReply.ledUnsupported.text) }
        AppLanguage.$forced.withValue(.ko) { #expect(HelperReply.noReply.text == "헬퍼에 연결하지 못했거나 3초 안에 응답이 없습니다.") }
    }
    @Test func ledUnsupportedFromCodeOrV2Text() {
        #expect(MagSafeLEDPolicy.outcome(reply:"led.unsupported") == (true,true))
        #expect(MagSafeLEDPolicy.outcome(reply:MagSafeLEDText.legacyUnsupportedV2) == (true,true))
        #expect(MagSafeLEDPolicy.outcome(reply:"이 맥에서는 MagSafe LED를 바꿀 수 없습니다.") == (true,true))
        #expect(MagSafeLEDPolicy.outcome(reply:"led.failed") == (false,false))
    }
    @Test func v2HelperIsOutdated() { #expect(HelperStatus.evaluate(installed:true,appPath:"/Applications/VibeBattery.app",probe:{true},version:{2}) == .outdated) }
    @Test func ownSigningDoesNotCrashWhenUnsigned() {
        switch CodeSigningIdentity.own {
        case .adHoc:break
        case .team(let t):#expect(t.count == 10)
        case .unknown(let s):Issue.record("signature unreadable: \(s)")
        }
    }
    @Test func reinstallReasonMentionsOfficialApp() {
        AppLanguage.$forced.withValue(.en) { #expect(LowPowerText.unavailable(.outdated) == "Reinstall the helper: this version only accepts the official VibeBattery app.") }
    }
    /// A successful script run is confirmed only when the helper ends up in the state the script was for.
    @Test func confirmationAfterScript() {
        AppLanguage.$forced.withValue(.en) {
            #expect(HelperStatus.ready.confirmation(afterInstall:true) == "The helper is installed and ready.")
            #expect(HelperStatus.notInstalled.confirmation(afterInstall:false) == "The helper is removed.")
            #expect(HelperStatus.unreachable.confirmation(afterInstall:true) == nil)
            #expect(HelperStatus.outdated.confirmation(afterInstall:true) == nil)
            #expect(HelperStatus.ready.confirmation(afterInstall:false) == nil)
        }
        AppLanguage.$forced.withValue(.ko) {
            #expect(HelperStatus.ready.confirmation(afterInstall:true) == "헬퍼를 설치했습니다. 바로 사용할 수 있습니다.")
            #expect(HelperStatus.notInstalled.confirmation(afterInstall:false) == "헬퍼를 제거했습니다.")
        }
    }
}
