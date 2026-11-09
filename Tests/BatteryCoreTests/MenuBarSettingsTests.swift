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
    @Test func pluggedInWhileTheBatteryRunsTheMac() {
        #expect(MenuBarStatus.make(onAC:true,charging:false,heatHolding:false,batteryWatts: -10) == .pluggedDischarging)
        #expect(MenuBarStatus.make(onAC:true,charging:false,heatHolding:false,batteryWatts: -0.3) == .paused)
        #expect(MenuBarStatus.make(onAC:true,charging:false,heatHolding:true,batteryWatts: -10) == .heatHold)
        #expect(MenuBarStatus.make(onAC:false,charging:false,heatHolding:false,batteryWatts: -10) == .onBattery)
    }
    @Test func eachStateHasAnImageAndAWord() {
        AppLanguage.$forced.withValue(.ko) {
            #expect(MenuBarStatus.charging.symbolName(percent:76) == "bolt.fill")
            #expect(MenuBarStatus.paused.symbolName(percent:70) == "powerplug.fill")
            #expect(MenuBarStatus.heatHold.symbolName(percent:70) == "thermometer.medium")
            #expect(MenuBarStatus.onBattery.symbolName(percent:55) == "battery.50percent")
            #expect(MenuBarStatus.pluggedDischarging.symbolName(percent:76) == "battery.75percent")
            #expect([MenuBarStatus.charging,.paused,.onBattery,.pluggedDischarging,.heatHold].map(\.title) == ["충전 중","유지","사용 중","사용 중","과열 보류"])
        }
        AppLanguage.$forced.withValue(.en) {
            #expect([MenuBarStatus.charging,.paused,.onBattery,.pluggedDischarging,.heatHold].map(\.title) == ["Charging","Holding","On battery","On battery","Heat hold"])
        }
    }
    @Test func batterySymbolFollowsTheLevel() {
        #expect([100,88,87,63,62,38,37,13,12,0].map { BatterySymbol.name(percent:$0) } == ["battery.100percent","battery.100percent","battery.75percent","battery.75percent","battery.50percent","battery.50percent","battery.25percent","battery.25percent","battery.0percent","battery.0percent"])
        #expect(BatterySymbol.name(percent:nil) == "battery.50percent")
    }
    @Test func menuBarTextPerStyle() {
        AppLanguage.$forced.withValue(.ko) {
            #expect(MenuBarText.make(style:.iconAndPercent,showsStatus:true,percent:76,status:.charging) == "76% 충전 중")
            #expect(MenuBarText.make(style:.iconAndPercent,showsStatus:false,percent:76,status:.charging) == "76%")
            #expect(MenuBarText.make(style:.iconOnly,showsStatus:true,percent:70,status:.paused) == "유지")
            #expect(MenuBarText.make(style:.iconOnly,showsStatus:false,percent:70,status:.paused) == nil)
            #expect(MenuBarText.make(style:.percentOnly,showsStatus:true,percent:76,status:.charging) == "76% 충전 중")
            #expect(MenuBarText.make(style:.percentOnly,showsStatus:false,percent:76,status:.charging) == "⚡︎76%")
            #expect(MenuBarText.make(style:.percentOnly,showsStatus:false,percent:76,status:.pluggedDischarging) == "76%")
            #expect(MenuBarText.make(style:.iconAndPercent,showsStatus:true,percent:nil,status:.onBattery) == "—% 사용 중")
        }
    }
    @Test func statusWordsAreOnByDefaultAndOldFilesKeepTheirStyle() throws {
        #expect(MenuBarSettings().showsStatus)
        let s=try JSONDecoder().decode(MenuBarSettings.self,from:Data(#"{"icon":"percentOnly"}"#.utf8))
        #expect(s.icon == .percentOnly);#expect(s.showsStatus)
        var off=MenuBarSettings();off.showsStatus=false
        #expect(try JSONDecoder().decode(MenuBarSettings.self,from:JSONEncoder().encode(off)).showsStatus == false)
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
