import Testing
import Foundation
@testable import BatteryCore
struct NotificationSettingsTests {
    @Test func scheduleNotificationDefaults() throws {
        let s=NotificationSettings()
        #expect(s.scheduleFailed);#expect(!s.scheduleRan)
        let old=try JSONDecoder().decode(NotificationSettings.self,from:Data(#"{"topUpDone":false}"#.utf8))
        #expect(old.scheduleFailed);#expect(!old.scheduleRan);#expect(!old.topUpDone)
    }
    @Test func chargeSectionRoutes() { #expect(AlertEvent.route("charge")=="charge") }
    @Test func defaultsTurnOnOnlyCostlyMisses() {
        let s=NotificationSettings()
        #expect(s.topUpDone && s.limitChanged && s.controlUnavailable && s.highTemperature && s.conflict && s.heatProblem && s.sessionEnded && s.protectionReleased && s.sleepDrain)
        #expect(!s.limitReached && !s.lowBattery && !s.heatActivity && !s.sessionCancelled && !s.suggestions && !s.weeklySummary)
        #expect(s.lowAt==20);#expect(s.hotAt==40)
    }
    @Test func missingKeysKeepDefaultsAndPreferencesLoadOldFiles() throws {
        let s=try JSONDecoder().decode(NotificationSettings.self,from:Data(#"{"lowBattery":true,"lowAt":30}"#.utf8))
        #expect(s.lowBattery);#expect(s.lowAt==30);#expect(s.topUpDone)
        let p=try JSONDecoder().decode(UserPreferences.self,from:Data(#"{"hours":8}"#.utf8))
        #expect(p.notifications==NotificationSettings())
    }
    @Test func thresholdsAreValidated() {
        var p=UserPreferences();p.notifications.lowAt=7;p.notifications.hotAt=60;p.validate()
        #expect(p.notifications.lowAt==20);#expect(p.notifications.hotAt==40)
        p.notifications.lowAt=35;p.notifications.hotAt=38;p.validate()
        #expect(p.notifications.lowAt==35);#expect(p.notifications.hotAt==38)
        p.notifications.lowAt=33;p.notifications.hotAt = .nan;p.validate()
        #expect(p.notifications.lowAt==20);#expect(p.notifications.hotAt==40)
    }
    @Test func memoryToleratesMissingAndUnknownKeys() throws {
        let json=#"{"hotArmed":false,"origin":"futureCase","newKey":1,"sessions":{"a":{}}}"#
        let m=try JSONDecoder().decode(NotificationMemory.self,from:Data(json.utf8))
        #expect(!m.hotArmed);#expect(m.lowArmed);#expect(m.origin==nil);#expect(m.sessions["a"]==SessionMark())
    }
    @Test func inProcessFieldsAreNotSaved() throws {
        var m=NotificationMemory();m.evaluated=Date();m.wasCharging=true;m.origin = .vibeBattery
        let back=try JSONDecoder().decode(NotificationMemory.self,from:JSONEncoder().encode(m))
        #expect(back.evaluated==nil);#expect(back.wasCharging==nil);#expect(back.origin == .vibeBattery)
    }
    @Test func clickedNotificationsOpenOnlyKnownScreens() {
        #expect(AlertEvent.route("health")=="health");#expect(AlertEvent.route("sessions")=="sessions")
        #expect(AlertEvent.route("../etc")=="dashboard");#expect(AlertEvent.route(nil)=="dashboard");#expect(AlertEvent.route(3)=="dashboard")
    }
    @Test func heatEventFromStepResult() {
        #expect(HeatEvent.from(action:.hold(70),failed:false) == .held(70))
        #expect(HeatEvent.from(action:.hold(70),failed:true) == .holdFailed)
        #expect(HeatEvent.from(action:.restore(.clearLimit),failed:false) == .restored)
        #expect(HeatEvent.from(action:.restore(.clearLimit),failed:true)==nil)
        #expect(HeatEvent.from(action:.yielded,failed:false) == .yielded)
        #expect(HeatEvent.from(action:.sensorUnavailable,failed:false)==nil)
    }
    @Test func durationText() {
        #expect(NotificationText.duration(59)=="1분");#expect(NotificationText.duration(3600)=="1시간")
        #expect(NotificationText.duration(4800)=="1시간 20분");#expect(NotificationText.duration(-5)=="0분")
    }
}
