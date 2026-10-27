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
    @Test func requirementTextFollowsLanguage() {
        AppLanguage.$forced.withValue(.en) { #expect(ChargeSupport.requirementText.hasPrefix("Charge limiting needs macOS 26.4")) }
        AppLanguage.$forced.withValue(.ko) { #expect(ChargeSupport.requirementText.hasPrefix("충전 상한은 macOS 26.4")) }
    }
}
