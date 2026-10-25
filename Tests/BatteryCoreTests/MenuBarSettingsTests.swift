import Testing
import Foundation
@testable import BatteryCore
struct MenuBarSettingsTests {
    @Test func statusPrecedence() {
        #expect(MenuBarStatus.make(onAC:true,charging:true,heatHolding:true) == .heatHold)
        #expect(MenuBarStatus.make(onAC:true,charging:true,heatHolding:false) == .charging)
        #expect(MenuBarStatus.make(onAC:true,charging:false,heatHolding:false) == .paused)
        #expect(MenuBarStatus.make(onAC:false,charging:false,heatHolding:false) == .onBattery)
    }
    @Test func defaultSections() {
        let s=MenuBarSettings()
        #expect(s == .default)
        #expect(s.sections.filter(\.visible).map(\.section) == [.status,.power,.limit,.lowPower,.battery,.sessions])
        #expect(s.sections.first{$0.section == .topUp}?.visible == false)
        #expect(MenuQuick.limits == [60,70,80,90,100])
    }
    @Test func decodeDropsUnknownAndAppendsMissing() throws {
        let json=#"{"icon":"weird","sections":[{"section":"battery","visible":false},{"section":"ghost","visible":true},{"section":"battery","visible":true}]}"#
        let s=try JSONDecoder().decode(MenuBarSettings.self,from:Data(json.utf8))
        #expect(s.icon == .iconAndPercent)
        #expect(s.sections.first == .init(section:.battery,visible:false))
        #expect(s.sections.count == 7)
        #expect(s.sections.last == .init(section:.sessions,visible:true))
        #expect(s.sections.first{$0.section == .topUp}?.visible == false)
    }
    @Test func moveClamps() {
        var s=MenuBarSettings()
        s.move(.status,by:-1)
        #expect(s == .default)
        s.move(.status,by:1)
        #expect(s.sections[0].section == .power);#expect(s.sections[1].section == .status)
    }
    @Test func oldPreferencesKeepOtherSettings() throws {
        let p=try JSONDecoder().decode(UserPreferences.self,from:Data(#"{"hours":6}"#.utf8))
        #expect(p.hours == 6);#expect(p.menuBar == .default)
    }
}
