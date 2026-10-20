import Testing
import BatteryCore
struct ChargeControllerDetectorTests {
    @Test func runningAlDenteIsDetected() {
        let r=ChargeControllerDetector.detect(runningBundleIDs:["com.apple.finder","com.apphousekitchen.aldente-pro"],systemItems:[])
        #expect(r==[OtherChargeController(name:"AlDente",evidence:"실행 중: com.apphousekitchen.aldente-pro")])
    }
    @Test func leftoverDaemonAfterAppDeletionStillBlocks() {
        let r=ChargeControllerDetector.detect(runningBundleIDs:[],systemItems:["/Library/LaunchDaemons/com.apphousekitchen.aldente-pro.helper.plist"])
        #expect(r.map(\.name)==["AlDente"])
    }
    @Test func battDaemonIsDetected() {
        #expect(ChargeControllerDetector.detect(runningBundleIDs:[],systemItems:["/Library/LaunchDaemons/cc.chlc.batt.plist"]).map(\.name)==["batt"])
    }
    @Test func ownHelperAndUnrelatedItemsAreIgnored() {
        let r=ChargeControllerDetector.detect(runningBundleIDs:["io.github.y-minion.vibebattery"],systemItems:[
            "/Library/LaunchDaemons/io.github.y-minion.vibebattery.helper.plist",
            "/Library/PrivilegedHelperTools/io.github.y-minion.vibebattery.helper",
            "/Library/LaunchDaemons/com.docker.vmnetd.plist"])
        #expect(r.isEmpty)
    }
}
