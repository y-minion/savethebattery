import Testing
import Foundation
@testable import BatteryCore
struct MagSafeLEDTests {
    @Test func systemTargetsNothing() {
        for s in [MenuBarStatus.charging,.paused,.onBattery,.heatHold] { #expect(MagSafeLEDPolicy.target(LEDSettings(),status:s) == nil) }
    }
    @Test func offTargetsOff() {
        var s=LEDSettings();s.mode = .off
        #expect(MagSafeLEDPolicy.target(s,status:.charging) == .off)
        #expect(MagSafeLEDPolicy.target(s,status:.onBattery) == .off)
    }
    @Test func perStateMapsColors() {
        var s=LEDSettings();s.mode = .perState
        #expect(MagSafeLEDPolicy.target(s,status:.charging) == .orange)
        #expect(MagSafeLEDPolicy.target(s,status:.paused) == .green)
        #expect(MagSafeLEDPolicy.target(s,status:.heatHold) == .orange)
        #expect(MagSafeLEDPolicy.target(s,status:.onBattery) == nil)
    }
    @Test func sameStateWritesNothing() { #expect(MagSafeLEDPolicy.write(target:.green,last:.green,dirty:true) == nil) }
    @Test func changedStateWrites() { #expect(MagSafeLEDPolicy.write(target:.orange,last:.green,dirty:true) == .orange) }
    @Test func dirtyFlagResetsOnceOnLaunch() {
        #expect(MagSafeLEDPolicy.write(target:nil,last:nil,dirty:true) == .system)
        #expect(MagSafeLEDPolicy.write(target:nil,last:.system,dirty:false) == nil)
    }
    @Test func cleanSystemWritesNothing() { #expect(MagSafeLEDPolicy.write(target:nil,last:nil,dirty:false) == nil) }
    @Test func oldPreferencesGetSystemLED() throws {
        let p=try JSONDecoder().decode(UserPreferences.self,from:Data(#"{"hours":6}"#.utf8))
        #expect(p.led.mode == .system);#expect(p.hours == 6)
        let q=try JSONDecoder().decode(UserPreferences.self,from:Data(#"{"led":{"mode":"weird","charging":"green"}}"#.utf8))
        #expect(q.led.mode == .system);#expect(q.led.charging == .green);#expect(q.led.paused == .green)
    }
}
