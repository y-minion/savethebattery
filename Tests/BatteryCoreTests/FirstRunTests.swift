import Testing
import Foundation
import BatteryCore
struct FirstRunTests {
    @Test func onlyTheApplicationsCopyStaysPut() {
        #expect(!FirstRun.needsMove(bundlePath:"/Applications/Save the Battery.app"))
        #expect(!FirstRun.needsMove(bundlePath:"/Applications/Save the Battery.app/"))
        #expect(FirstRun.needsMove(bundlePath:"/Users/u/Downloads/Save the Battery.app"))
        #expect(FirstRun.needsMove(bundlePath:"/Volumes/Save the Battery/Save the Battery.app"))
        #expect(FirstRun.needsMove(bundlePath:"/private/var/folders/x/AppTranslocation/1234/d/Save the Battery.app"))
        #expect(FirstRun.needsMove(bundlePath:"/Applications/Utilities/../Save the Battery 2.app"))
        #expect(HelperPolicy.appPrefix == HelperPolicy.appPath+"/")
    }
    @Test func theDiskImageCopyIsNeverTrashed() {
        #expect(FirstRun.trashesOriginal(path:"/Users/u/Downloads/Save the Battery.app",readOnlyVolume:false))
        #expect(!FirstRun.trashesOriginal(path:"/Volumes/Save the Battery/Save the Battery.app",readOnlyVolume:true))
        #expect(!FirstRun.trashesOriginal(path:"/Applications/Save the Battery.app",readOnlyVolume:false))
    }
    @Test func eightyPercentIsSuggestedOnlyWithoutALimit() {
        let off=ChargeLimitState(supported:true,enabled:false,limit:nil)
        #expect(FirstRun.suggestsLimit(off,conflicts:false,dismissed:false))
        #expect(FirstRun.suggestsLimit(ChargeLimitState(supported:true,enabled:true,limit:100),conflicts:false,dismissed:false))
        #expect(!FirstRun.suggestsLimit(ChargeLimitState(supported:true,enabled:true,limit:80),conflicts:false,dismissed:false))
        #expect(!FirstRun.suggestsLimit(ChargeLimitState(supported:true,enabled:true,limit:70),conflicts:false,dismissed:false))
        #expect(!FirstRun.suggestsLimit(off,conflicts:true,dismissed:false))
        #expect(!FirstRun.suggestsLimit(off,conflicts:false,dismissed:true))
        #expect(!FirstRun.suggestsLimit(ChargeLimitState(supported:false),conflicts:false,dismissed:false))
        #expect(!FirstRun.suggestsLimit(ChargeLimitState(),conflicts:false,dismissed:false))
    }
    @Test func dismissedTipSurvivesAndOldFilesDecode() throws {
        #expect(!(try JSONDecoder().decode(UserPreferences.self,from:Data("{}".utf8))).limitTipDismissed)
        var p=UserPreferences();p.limitTipDismissed=true
        let back=try JSONDecoder().decode(UserPreferences.self,from:JSONEncoder().encode(p))
        #expect(back.limitTipDismissed)
    }
}
