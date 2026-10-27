import Testing
import BatteryCore
struct ChargeControllerDetectorTests {
    @Test func runningAlDenteIsDetected() {
        AppLanguage.$forced.withValue(.ko) {
            let r=ChargeControllerDetector.detect(runningBundleIDs:["com.apple.finder","com.apphousekitchen.aldente-pro"],systemItems:[])
            #expect(r==[OtherChargeController(name:"AlDente",evidence:"실행 중: com.apphousekitchen.aldente-pro")])
        }
    }
    @Test func leftoverDaemonAfterAppDeletionStillBlocks() {
        AppLanguage.$forced.withValue(.ko) {
            let r=ChargeControllerDetector.detect(runningBundleIDs:[],systemItems:["/Library/LaunchDaemons/com.apphousekitchen.aldente-pro.helper.plist"])
            #expect(r.map(\.name)==["AlDente"])
        }
    }
    @Test func battDaemonIsDetected() {
        AppLanguage.$forced.withValue(.ko) {
            #expect(ChargeControllerDetector.detect(runningBundleIDs:[],systemItems:["/Library/LaunchDaemons/cc.chlc.batt.plist"]).map(\.name)==["batt"])
        }
    }
    @Test func ownHelperAndUnrelatedItemsAreIgnored() {
        AppLanguage.$forced.withValue(.ko) {
            let r=ChargeControllerDetector.detect(runningBundleIDs:["io.github.y-minion.vibebattery"],systemItems:[
                "/Library/LaunchDaemons/io.github.y-minion.vibebattery.helper.plist",
                "/Library/PrivilegedHelperTools/io.github.y-minion.vibebattery.helper",
                "/Library/LaunchDaemons/com.docker.vmnetd.plist"])
            #expect(r.isEmpty)
        }
    }
    @Test func batteryCLIAndBatteryToolkitAreDetected() {
        AppLanguage.$forced.withValue(.ko) {
            let home="/Users/u/Library/LaunchAgents/battery.plist"
            #expect(ChargeControllerDetector.detect(runningBundleIDs:[],systemItems:[home]).map(\.name)==["battery"])
            #expect(ChargeControllerDetector.detect(runningBundleIDs:["co.palokaj.battery"],systemItems:[]).map(\.name)==["battery"])
            #expect(ChargeControllerDetector.detect(runningBundleIDs:[],systemItems:["/Applications/Battery Toolkit.app"]).map(\.name)==["Battery Toolkit"])
            #expect(ChargeControllerDetector.detect(runningBundleIDs:["me.mhaeuser.BatteryToolkit"],systemItems:[]).map(\.name)==["Battery Toolkit"])
            #expect(ChargeControllerDetector.detect(runningBundleIDs:[],systemItems:["/Applications/VibeBattery.app","/Applications/AlDente.app.bak/x"]).isEmpty)
        }
    }
}
