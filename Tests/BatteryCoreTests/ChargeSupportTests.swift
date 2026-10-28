import Testing
import Foundation
@testable import BatteryCore

struct ChargeSupportTests {
    @Test func gate() {
        #expect(!ChargeSupport.platformAllows(os:.init(majorVersion:26,minorVersion:3,patchVersion:9),arm64:true))
        #expect(ChargeSupport.platformAllows(os:.init(majorVersion:26,minorVersion:4,patchVersion:0),arm64:true))
        #expect(ChargeSupport.platformAllows(os:.init(majorVersion:27,minorVersion:0,patchVersion:1),arm64:true))
        #expect(!ChargeSupport.platformAllows(os:.init(majorVersion:27,minorVersion:0,patchVersion:0),arm64:false))
        #expect(!ChargeSupport.platformAllows(os:.init(majorVersion:15,minorVersion:7,patchVersion:0),arm64:true))
    }
    /// Apple silicon is told to update macOS; Intel is told it is not supported, with no promise.
    @Test func requirementTextFollowsLanguageAndChip() {
        AppLanguage.$forced.withValue(.en) {
            #expect(ChargeSupport.requirementText(arm64:true).hasPrefix("Charge limiting needs macOS 26.4"))
            #expect(ChargeSupport.requirementText(arm64:true).contains("Software Update"))
            #expect(ChargeSupport.requirementText(arm64:false) == "Charge limiting doesn't support Intel Macs yet.")
        }
        AppLanguage.$forced.withValue(.ko) {
            #expect(ChargeSupport.requirementText(arm64:true).hasPrefix("충전 상한은 macOS 26.4"))
            #expect(ChargeSupport.requirementText(arm64:true).contains("소프트웨어 업데이트"))
            #expect(ChargeSupport.requirementText(arm64:false) == "충전 상한은 아직 Intel 맥을 지원하지 않습니다.")
        }
    }
    /// A Mac that passes the gate but where macOS reports no charge limit gets its own text, not the requirement.
    @Test func unsupportedTextSeparatesGateFromMac() {
        AppLanguage.$forced.withValue(.en) {
            #expect(ChargeSupport.unsupportedText(platformAllows:false) == ChargeSupport.requirementText())
            #expect(ChargeSupport.unsupportedText(platformAllows:true) == "Charge limiting isn't available on this Mac.")
        }
        AppLanguage.$forced.withValue(.ko) { #expect(ChargeSupport.unsupportedText(platformAllows:true) == "이 맥에서는 충전 상한을 쓸 수 없습니다.") }
    }
}
