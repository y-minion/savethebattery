import Testing
import Foundation
@testable import BatteryCore
@testable import BatteryPlatform

struct HelperV3Tests {
    @Test func pinnedRequirement() {
        #expect(HelperPolicy.requirement(identifier:"io.github.y-minion.vibebattery",team:"JQWWU7443A") ==
          "identifier \"io.github.y-minion.vibebattery\" and anchor apple generic and certificate leaf[subject.OU] = \"JQWWU7443A\"")
        #expect(HelperPolicy.requirement(identifier:"io.github.y-minion.vibebattery",team:nil) == "identifier \"io.github.y-minion.vibebattery\"")
        #expect(HelperPolicy.clientRequirement(team:nil) == "identifier \"io.github.y-minion.vibebattery\"")
        #expect(HelperPolicy.helperRequirement(team:"JQWWU7443A").hasPrefix("identifier \"io.github.y-minion.vibebattery.helper\" and anchor apple generic"))
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
    @Test func ownTeamIDDoesNotCrashWhenUnsigned() {
        let t=CodeSigningIdentity.ownTeamID()
        #expect(t == nil || t?.count == 10)
    }
    @Test func reinstallReasonMentionsOfficialApp() {
        AppLanguage.$forced.withValue(.en) { #expect(LowPowerText.unavailable(.outdated) == "Reinstall the helper: this version only accepts the official VibeBattery app.") }
    }
}
