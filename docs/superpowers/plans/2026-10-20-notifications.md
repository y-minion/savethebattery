# Local Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notify the user about charge state, battery protection problems, vibe-coding session endings and health findings, each switchable, without repeats.

**Architecture:** A pure `NotificationPolicy.evaluate(input, settings, memory)` in `BatteryCore` returns alerts, removals and new memory. `BatteryPlatform` persists the memory in `notify.json`. The app builds the input after each 30 s refresh and on wake, delivers alerts through `UNUserNotificationCenter` only when running as a bundled `.app`, and routes clicks to an allow-listed screen.

**Tech Stack:** Swift 6 toolchain in Swift 5 mode, SwiftPM, Swift Testing, SwiftUI/AppKit, UserNotifications.

**Spec:** `docs/superpowers/specs/2026-10-20-notifications-design.md`

## Global Constraints

- Local build/test: `SW=/Users/youngmin/Documents/Codex/2026-10-18/a/work/swift-local; $SW test --disable-xctest`. `work/` stays out of Git.
- Never change the real charge limit, never quit or delete other apps, never touch the running VibeBattery (PID 12635) or `~/Library/Application Support/VibeBattery` (read-only is fine). Smoke runs use `VIBEBATTERY_DATA_DIR` in the scratchpad.
- No personal device values in Git.
- Default on: topUpDone, limitChanged, controlUnavailable, highTemperature, conflict, heatProblem, sessionEnded, protectionReleased, sleepDrain. Default off: limitReached, lowBattery, heatActivity, sessionCancelled, suggestions, weeklySummary. lowAt 20 (10–50, step 5), hotAt 40 (36–45), on battery +2 °C.
- Notification permission is requested only from the Settings button, never at launch.
- Session alerts carry only the executable name and duration, never arguments.
- Allowed click targets: `dashboard`, `settings`, `sessions`, `health`; anything else opens `dashboard`.
- Commit messages: English conventional style ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_0198mefMcqqi2XyQ77EcLore`.

## Review Focus

1. Limit origin flapping between `vibeBattery` and `external` because of the app's own writes (heat hold, restore, top-up) — must never alert; covered in Task 2 `limitChangedOnlyWhenSomeoneElseChangesIt`.
2. App restart or sleep producing a false "limit reached" or a burst of old session endings — Task 2 `limitReachedNeedsAnObservedChargingStep`, Task 4 `sessionsFirstSeenAfterEndingAreAnnouncedOnlyIfRecent`.
3. Wall clock moved backwards leaving cooldowns stuck forever — Task 5 `timestampsFromTheFutureCountAsExpired`.
4. Running outside an `.app` bundle (tests, `swift run`) crashing in UserNotifications — Task 7 guards with `NotificationRuntime.bundled`; smoke-run check.
5. Turning an event on later causing a backlog — Task 5 `disabledEventsStillAdvanceMemory`.

---

### Task 1: Notification types, settings and preferences

**Files:**
- Create: `Sources/BatteryCore/NotificationTypes.swift`
- Create: `Sources/BatteryCore/NotificationText.swift`
- Modify: `Sources/BatteryCore/UserPreferences.swift`
- Test: `Tests/BatteryCoreTests/NotificationSettingsTests.swift`

**Interfaces:**
- Produces: `NotificationSettings` (Bool flags listed in Global Constraints, `lowAt:Int`, `hotAt:Double`, `validate()`), `HeatEvent { held(Int), restored, yielded, holdFailed }` with `static from(action:HeatAction,failed:Bool)->HeatEvent?`, `SessionSummary(id:UUID,command:String,outcome:SessionOutcome,started:Date,ended:Date?=nil,exitCode:Int32?=nil,released:Bool=false)`, `NotificationInput(now:Date,battery:BatterySnapshot)` with vars `limit,lastWritten,topUpRequested,heatEnabled,heatHolding,heatStuckLimit,heatSensorMissing,heatEvent,conflicts,sessions,wake,suggestions:[Suggestion],week:UsageSummary?,calendar`, `AlertEvent(id:title:body:section:thread:duplicatesAppMessage:)` with `static route(_:Any?)->String`, `NotificationOutcome(events,removals,memory)` with `mutating send(_ on:Bool,_ e:AlertEvent)` and `mutating remove(_ id:String)`, `NotificationMemory` (fields below), `SessionMark(ended:released:)`, `UserPreferences.notifications`, `NotificationText.duration(_:)`.

- [ ] **Step 1: Write the failing test**

`Tests/BatteryCoreTests/NotificationSettingsTests.swift`:

```swift
import Testing
import Foundation
@testable import BatteryCore
struct NotificationSettingsTests {
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$SW test --disable-xctest --filter NotificationSettingsTests`
Expected: FAIL — compile errors, `NotificationSettings` not found.

- [ ] **Step 3: Write minimal implementation**

`Sources/BatteryCore/NotificationTypes.swift`:

```swift
import Foundation
/// Which notifications the user wants and their thresholds. Missing keys keep defaults so older files load.
public struct NotificationSettings: Codable, Equatable, Sendable {
    public var limitReached=false, topUpDone=true, lowBattery=false, limitChanged=true, controlUnavailable=true
    public var highTemperature=true, conflict=true, heatProblem=true, heatActivity=false
    public var sessionEnded=true, sessionCancelled=false, protectionReleased=true
    public var sleepDrain=true, suggestions=false, weeklySummary=false
    public var lowAt=20
    public var hotAt=40.0
    public static let lowRange=10...50, hotRange=36.0...45.0
    public init() {}
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self),d=NotificationSettings()
        func flag(_ k:CodingKeys,_ v:Bool) throws -> Bool { try c.decodeIfPresent(Bool.self,forKey:k) ?? v }
        limitReached=try flag(.limitReached,d.limitReached);topUpDone=try flag(.topUpDone,d.topUpDone)
        lowBattery=try flag(.lowBattery,d.lowBattery);limitChanged=try flag(.limitChanged,d.limitChanged)
        controlUnavailable=try flag(.controlUnavailable,d.controlUnavailable);highTemperature=try flag(.highTemperature,d.highTemperature)
        conflict=try flag(.conflict,d.conflict);heatProblem=try flag(.heatProblem,d.heatProblem);heatActivity=try flag(.heatActivity,d.heatActivity)
        sessionEnded=try flag(.sessionEnded,d.sessionEnded);sessionCancelled=try flag(.sessionCancelled,d.sessionCancelled)
        protectionReleased=try flag(.protectionReleased,d.protectionReleased);sleepDrain=try flag(.sleepDrain,d.sleepDrain)
        suggestions=try flag(.suggestions,d.suggestions);weeklySummary=try flag(.weeklySummary,d.weeklySummary)
        lowAt=try c.decodeIfPresent(Int.self,forKey:.lowAt) ?? d.lowAt
        hotAt=try c.decodeIfPresent(Double.self,forKey:.hotAt) ?? d.hotAt
    }
    public mutating func validate() {
        if !Self.lowRange.contains(lowAt) || lowAt%5 != 0 { lowAt=20 }
        if !hotAt.isFinite || !Self.hotRange.contains(hotAt) { hotAt=40 }
    }
}
/// What one heat-hold step did, announced once.
public enum HeatEvent: Equatable, Sendable {
    case held(Int), restored, yielded, holdFailed
    /// A failed restore is not an event: it leaves a stuck limit, which is reported as state.
    public static func from(action:HeatAction,failed:Bool) -> HeatEvent? {
        switch action {
        case .hold(let p):return failed ? .holdFailed:.held(p)
        case .restore:return failed ? nil:.restored
        case .yielded:return .yielded
        default:return nil
        }
    }
}
public struct SessionSummary: Equatable, Sendable {
    public var id:UUID;public var command:String;public var outcome:SessionOutcome
    public var started:Date;public var ended:Date?;public var exitCode:Int32?
    /// The user asked VibeBattery to release this session's protection.
    public var released:Bool
    public init(id:UUID,command:String,outcome:SessionOutcome,started:Date,ended:Date?=nil,exitCode:Int32?=nil,released:Bool=false) {
        self.id=id;self.command=command;self.outcome=outcome;self.started=started;self.ended=ended;self.exitCode=exitCode;self.released=released
    }
}
/// Everything one evaluation looks at. One-shot fields (`heatEvent`, `wake`) are set only for the refresh that produced them.
public struct NotificationInput: Sendable {
    public var now:Date
    public var battery:BatterySnapshot
    public var limit=ChargeLimitState()
    public var lastWritten:Int?
    public var topUpRequested:Date?
    public var heatEnabled=false, heatHolding=false
    /// The lowered limit left behind by a failed restore.
    public var heatStuckLimit:Int?
    public var heatSensorMissing=false
    public var heatEvent:HeatEvent?
    public var conflicts:[String]=[]
    public var sessions:[SessionSummary]=[]
    public var wake:SleepEvent?
    public var suggestions:[Suggestion]=[]
    public var week:UsageSummary?
    public var calendar=Calendar.current
    public init(now:Date,battery:BatterySnapshot) { self.now=now;self.battery=battery }
}
public struct AlertEvent: Equatable, Sendable {
    public static let sections:Set<String>=["dashboard","settings","sessions","health"]
    /// The screen a clicked notification may open; anything unexpected opens the dashboard.
    public static func route(_ value:Any?) -> String { (value as? String).flatMap { sections.contains($0) ? $0:nil } ?? "dashboard" }
    /// Same id replaces the earlier notification of that kind.
    public var id:String, title:String, body:String, section:String, thread:String
    /// The app also shows this in its own alert; skipped while the app is in front.
    public var duplicatesAppMessage:Bool
    public init(id:String,title:String,body:String,section:String,thread:String,duplicatesAppMessage:Bool=false) {
        self.id=id;self.title=title;self.body=body;self.section=section;self.thread=thread;self.duplicatesAppMessage=duplicatesAppMessage
    }
}
public struct SessionMark: Codable, Equatable, Sendable {
    public var ended=false, released=false
    public init(ended:Bool=false,released:Bool=false) { self.ended=ended;self.released=released }
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        ended=try c.decodeIfPresent(Bool.self,forKey:.ended) ?? false;released=try c.decodeIfPresent(Bool.self,forKey:.released) ?? false
    }
}
/// What has been announced and what may be announced again. Disabled events update it too, so enabling one later causes no backlog.
public struct NotificationMemory: Codable, Equatable, Sendable {
    /// In-process only: after a restart change-based checks start from a fresh baseline.
    public var evaluated:Date?
    public var wasCharging:Bool?
    public var limitNotified:Int?
    public var offACSince:Date?, onACSince:Date?
    public var topUpNotified:Date?
    public var lowArmed=true
    public var hotArmed=true
    public var hotSent:Date?
    public var conflicts:[String]=[]
    public var origin:LimitOrigin?
    public var lastWritten:Int?
    public var supportedSeen=false, unavailableNotified=false
    public var stuckSent:Date?
    public var sensorMissingSince:Date?
    public var sensorNotified=false
    public var sessions:[String:SessionMark]=[:]
    public var suggestionSent:[String:Date]=[:]
    public var weekKey:String?
    enum CodingKeys:String,CodingKey { case limitNotified,offACSince,onACSince,topUpNotified,lowArmed,hotArmed,hotSent,conflicts,origin,lastWritten,supportedSeen,unavailableNotified,stuckSent,sensorMissingSince,sensorNotified,sessions,suggestionSent,weekKey }
    public init() {}
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        limitNotified=try c.decodeIfPresent(Int.self,forKey:.limitNotified)
        offACSince=try c.decodeIfPresent(Date.self,forKey:.offACSince);onACSince=try c.decodeIfPresent(Date.self,forKey:.onACSince)
        topUpNotified=try c.decodeIfPresent(Date.self,forKey:.topUpNotified)
        lowArmed=try c.decodeIfPresent(Bool.self,forKey:.lowArmed) ?? true;hotArmed=try c.decodeIfPresent(Bool.self,forKey:.hotArmed) ?? true
        hotSent=try c.decodeIfPresent(Date.self,forKey:.hotSent)
        conflicts=try c.decodeIfPresent([String].self,forKey:.conflicts) ?? []
        origin=(try? c.decodeIfPresent(LimitOrigin.self,forKey:.origin)) ?? nil
        lastWritten=try c.decodeIfPresent(Int.self,forKey:.lastWritten)
        supportedSeen=try c.decodeIfPresent(Bool.self,forKey:.supportedSeen) ?? false
        unavailableNotified=try c.decodeIfPresent(Bool.self,forKey:.unavailableNotified) ?? false
        stuckSent=try c.decodeIfPresent(Date.self,forKey:.stuckSent)
        sensorMissingSince=try c.decodeIfPresent(Date.self,forKey:.sensorMissingSince)
        sensorNotified=try c.decodeIfPresent(Bool.self,forKey:.sensorNotified) ?? false
        sessions=try c.decodeIfPresent([String:SessionMark].self,forKey:.sessions) ?? [:]
        suggestionSent=try c.decodeIfPresent([String:Date].self,forKey:.suggestionSent) ?? [:]
        weekKey=try c.decodeIfPresent(String.self,forKey:.weekKey)
    }
    /// A wall clock moved back leaves times in the future: sent times expire, durations restart now.
    mutating func clamp(_ now:Date) {
        func since(_ d:Date?) -> Date? { d.map { $0>now ? now:$0 } }
        func sent(_ d:Date?) -> Date? { d.flatMap { $0>now ? nil:$0 } }
        evaluated=sent(evaluated);offACSince=since(offACSince);onACSince=since(onACSince);sensorMissingSince=since(sensorMissingSince)
        hotSent=sent(hotSent);stuckSent=sent(stuckSent);suggestionSent=suggestionSent.filter { $0.value<=now }
    }
}
public struct NotificationOutcome: Equatable, Sendable {
    public var events:[AlertEvent]=[]
    /// Delivered notifications whose condition has ended.
    public var removals:[String]=[]
    public var memory:NotificationMemory
    public init(memory:NotificationMemory) { self.memory=memory }
    mutating func send(_ on:Bool,_ e:AlertEvent) { if on { events.append(e) } }
    mutating func remove(_ id:String) { removals.append(id) }
}
```

`Sources/BatteryCore/NotificationText.swift`:

```swift
import Foundation
public enum NotificationText {
    public static func duration(_ seconds:TimeInterval) -> String {
        let m=max(0,Int((seconds/60).rounded()))
        if m<60 { return "\(m)분" }
        return m%60==0 ? "\(m/60)시간":"\(m/60)시간 \(m%60)분"
    }
}
```

`Sources/BatteryCore/UserPreferences.swift` — add the field, decode it, validate it:

```swift
    public var heat=HeatSettings()
    public var notifications=NotificationSettings()
```
in `init(from:)` after the `heat` line:
```swift
        notifications=try c.decodeIfPresent(NotificationSettings.self,forKey:.notifications) ?? NotificationSettings()
```
and `validate()` becomes:
```swift
    public mutating func validate() { if !hours.isFinite || hours<=0 || hours>168 { hours=4 };heat.validate();notifications.validate() }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `$SW test --disable-xctest --filter NotificationSettingsTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/BatteryCore/NotificationTypes.swift Sources/BatteryCore/NotificationText.swift Sources/BatteryCore/UserPreferences.swift Tests/BatteryCoreTests/NotificationSettingsTests.swift
git commit -m "feat: add notification settings, memory and event types"
```

---

### Task 2: Charge notifications

**Files:**
- Create: `Sources/BatteryCore/NotificationPolicy.swift`
- Modify: `Sources/BatteryCore/NotificationText.swift`
- Create: `Tests/BatteryCoreTests/NotificationTestSupport.swift`
- Test: `Tests/BatteryCoreTests/NotificationChargeTests.swift`

**Interfaces:**
- Consumes: Task 1 types.
- Produces: `NotificationPolicy.evaluate(_:settings:memory:) -> NotificationOutcome`, constants `gap`, `offACRearm`, `onACRearm`; `NT` test helper (`t0`, `utc`, `all`, `input(_:percent:onAC:charging:temp:)`, `run(_:_:memory:) -> [NotificationOutcome]`, `ids(_:)`). Later tasks add `protect`, `heat`, `sessions`, `health` calls inside `evaluate`.

- [ ] **Step 1: Write the failing test**

`Tests/BatteryCoreTests/NotificationTestSupport.swift`:

```swift
import Foundation
@testable import BatteryCore
enum NT {
    /// Monday 2026-09-21 14:13:20 UTC, ISO week 2026-W39.
    static let t0=Date(timeIntervalSince1970:1_790_000_000)
    static var utc:Calendar { var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:"UTC")!;return c }
    static var flags:[WritableKeyPath<NotificationSettings,Bool>] { [\.limitReached,\.topUpDone,\.lowBattery,\.limitChanged,\.controlUnavailable,\.highTemperature,\.conflict,\.heatProblem,\.heatActivity,\.sessionEnded,\.sessionCancelled,\.protectionReleased,\.sleepDrain,\.suggestions,\.weeklySummary] }
    static var all:NotificationSettings { var s=NotificationSettings();for k in flags { s[keyPath:k]=true };return s }
    /// A battery at `percent`, limit 80% written by VibeBattery.
    static func input(_ dt:Double,percent:Int?=60,onAC:Bool=true,charging:Bool=false,temp:Double?=30) -> NotificationInput {
        var b=BatterySnapshot();b.timestamp=t0+dt;b.percent=percent;b.onAC=onAC;b.charging=charging;b.temperature=temp
        var i=NotificationInput(now:t0+dt,battery:b)
        i.limit=ChargeLimitState(supported:true,enabled:true,limit:80);i.lastWritten=80;i.calendar=utc
        return i
    }
    /// Evaluates inputs in order, carrying memory.
    static func run(_ inputs:[NotificationInput],_ s:NotificationSettings=all,memory:NotificationMemory=NotificationMemory()) -> [NotificationOutcome] {
        var m=memory;var out:[NotificationOutcome]=[]
        for i in inputs { let o=NotificationPolicy.evaluate(i,settings:s,memory:m);m=o.memory;out.append(o) }
        return out
    }
    static func ids(_ o:[NotificationOutcome]) -> [[String]] { o.map { $0.events.map(\.id) } }
}
```

`Tests/BatteryCoreTests/NotificationChargeTests.swift`:

```swift
import Testing
import Foundation
@testable import BatteryCore
struct NotificationChargeTests {
    func at(_ dt:Double,_ p:Int,ac:Bool=true,charging:Bool=false) -> NotificationInput { NT.input(dt,percent:p,onAC:ac,charging:charging) }
    @Test func limitReachedWhenChargingStopsNearLimit() {
        let r=NT.run([at(0,78,charging:true),at(30,79),at(60,80)])
        #expect(NT.ids(r)==[[],["charge.limitReached"],[]])
        #expect(r[1].events[0].title.contains("80%"));#expect(r[1].events[0].section=="dashboard")
    }
    @Test func limitReachedNeedsAnObservedChargingStep() {
        #expect(NT.ids(NT.run([at(0,80)]))==[[]])
        // A gap (sleep, app closed) is a fresh baseline.
        #expect(NT.ids(NT.run([at(0,78,charging:true),at(400,80)]))==[[],[]])
    }
    @Test func limitReachedSkippedDuringHeatHoldAndTopUp() {
        var a=at(30,80);a.heatHolding=true
        #expect(NT.ids(NT.run([at(0,79,charging:true),a]))==[[],[]])
        var b=at(30,80);b.topUpRequested=NT.t0
        #expect(!NT.ids(NT.run([at(0,79,charging:true),b])).flatMap { $0 }.contains("charge.limitReached"))
    }
    @Test func limitReachedRearmsOnlyAfterLongUnplugOrNewLimit() {
        let brief=NT.run([at(0,79,charging:true),at(30,80),at(60,80,ac:false),at(90,79,charging:true),at(120,80)])
        #expect(NT.ids(brief).flatMap { $0 }==["charge.limitReached"])
        let long=NT.run([at(0,79,charging:true),at(30,80),at(60,80,ac:false),at(390,79,ac:false),at(420,79,charging:true),at(450,80)])
        #expect(NT.ids(long).flatMap { $0 }==["charge.limitReached","charge.limitReached"])
        var raised=at(90,84,charging:true);raised.limit.limit=85;raised.lastWritten=85
        var stop=at(120,85);stop.limit.limit=85;stop.lastWritten=85
        #expect(NT.ids(NT.run([at(0,79,charging:true),at(30,80),raised,stop])).flatMap { $0 }==["charge.limitReached","charge.limitReached"])
    }
    @Test func topUpDoneOncePerRequest() {
        func t(_ dt:Double,_ p:Int,_ requested:Double,charging:Bool=false) -> NotificationInput {
            var i=at(dt,p,charging:charging);i.topUpRequested=NT.t0+requested;i.limit.enabled=false;return i
        }
        let r=NT.run([t(0,98,0,charging:true),t(30,99,0,charging:true),t(60,100,0),t(90,100,90)])
        #expect(NT.ids(r)==[[],["charge.topUpDone"],[],["charge.topUpDone"]])
    }
    @Test func lowBatteryRearmsAfterRiseOrSteadyAdapter() {
        let r=NT.run([at(0,25,ac:false),at(30,20,ac:false),at(60,19,ac:false),at(90,19),at(120,19,ac:false),at(150,18,ac:false),at(180,19),at(330,20),at(360,20,ac:false)])
        #expect(NT.ids(r)==[[],["charge.low"],[],[],[],[],[],[],["charge.low"]])
        #expect(r[7].removals==["charge.low"])
        let rise=NT.run([at(0,20,ac:false),at(30,24,ac:false),at(60,25,ac:false),at(90,20,ac:false)])
        #expect(NT.ids(rise)==[["charge.low"],[],[],["charge.low"]])
    }
    @Test func limitChangedOnlyWhenSomeoneElseChangesIt() {
        var ext=at(30,60);ext.limit.limit=90
        let r=NT.run([at(0,60),ext]);#expect(NT.ids(r)==[[],["charge.limitChanged"]]);#expect(r[1].events[0].title.contains("90%"))
        var off=at(30,60);off.limit.enabled=false
        #expect(NT.ids(NT.run([at(0,60),off]))==[[],["charge.limitChanged"]])
        var mine=at(30,60);mine.limit.enabled=false;mine.lastWritten=nil
        var topUp=at(30,60);topUp.limit.enabled=false;topUp.topUpRequested=NT.t0
        var yielded=at(30,60);yielded.limit.limit=90;yielded.heatEvent = .yielded
        var restored=at(30,60);restored.limit.limit=90;restored.lastWritten=nil
        for x in [mine,topUp,yielded,restored] { #expect(!NT.ids(NT.run([at(0,60),x])).flatMap { $0 }.contains("charge.limitChanged")) }
        var unknown=at(30,60);unknown.limit.supported=nil
        var back=at(60,60);back.limit.limit=90
        #expect(NT.ids(NT.run([at(0,60),unknown,back]))==[[],[],["charge.limitChanged"]])
        let again=NT.run([at(0,60),ext,at(60,60)]);#expect(again[2].removals==["charge.limitChanged"])
    }
    @Test func controlUnavailableOnlyAfterSupportWasSeen() {
        var no=at(0,60);no.limit=ChargeLimitState(supported:false)
        #expect(NT.ids(NT.run([no]))==[[]])
        var later=at(30,60);later.limit=ChargeLimitState(supported:false)
        var again=at(60,60);again.limit=ChargeLimitState(supported:false)
        let r=NT.run([at(0,60),later,again,at(90,60)])
        #expect(NT.ids(r)==[[],["charge.unavailable"],[],[]]);#expect(r[3].removals==["charge.unavailable"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$SW test --disable-xctest --filter NotificationChargeTests`
Expected: FAIL — `NotificationPolicy` not found.

- [ ] **Step 3: Write minimal implementation**

`Sources/BatteryCore/NotificationPolicy.swift`:

```swift
import Foundation
public enum NotificationPolicy {
    /// Longer than this since the last evaluation (sleep, app closed) and change-based checks restart from a baseline.
    public static let gap:TimeInterval=300
    public static let offACRearm:TimeInterval=300, onACRearm:TimeInterval=120
    public static func evaluate(_ i:NotificationInput,settings s:NotificationSettings,memory:NotificationMemory) -> NotificationOutcome {
        var o=NotificationOutcome(memory:memory)
        o.memory.clamp(i.now)
        let continuous=o.memory.evaluated.map { i.now.timeIntervalSince($0)<=gap } ?? false
        charge(i,s,&o,continuous:continuous)
        o.memory.evaluated=i.now
        return o
    }
    static func charge(_ i:NotificationInput,_ s:NotificationSettings,_ o:inout NotificationOutcome,continuous:Bool) {
        let b=i.battery,now=i.now
        if let off=o.memory.offACSince,now.timeIntervalSince(off)>offACRearm { o.memory.limitNotified=nil }
        let steadyAC=b.onAC && (o.memory.onACSince.map { now.timeIntervalSince($0)>=onACRearm } ?? false)
        if b.onAC { o.memory.offACSince=nil;if o.memory.onACSince==nil { o.memory.onACSince=now } }
        else { o.memory.onACSince=nil;if o.memory.offACSince==nil { o.memory.offACSince=now } }
        if let n=o.memory.limitNotified,i.limit.enabled != true || i.limit.limit != n { o.memory.limitNotified=nil }
        if let p=b.percent {
            // Charging just stopped at the limit; the displayed percent is rounded, so one point short counts.
            if continuous,o.memory.wasCharging==true,b.onAC,!b.charging,i.limit.enabled==true,let l=i.limit.limit,p>=l-1,
               !i.heatHolding,i.topUpRequested==nil,o.memory.limitNotified==nil {
                o.memory.limitNotified=l
                let t=NotificationText.limitReached(l)
                o.send(s.limitReached,AlertEvent(id:"charge.limitReached",title:t.0,body:t.1,section:"dashboard",thread:"charge"))
            }
            if let r=i.topUpRequested,b.onAC,p>=99,o.memory.topUpNotified != r {
                o.memory.topUpNotified=r
                let t=NotificationText.topUpDone(p)
                o.send(s.topUpDone,AlertEvent(id:"charge.topUpDone",title:t.0,body:t.1,section:"dashboard",thread:"charge"))
            }
            if !o.memory.lowArmed,p>=s.lowAt+5 || steadyAC { o.memory.lowArmed=true;o.remove("charge.low") }
            if o.memory.lowArmed,!b.onAC,p<=s.lowAt {
                o.memory.lowArmed=false
                let t=NotificationText.lowBattery(p,at:s.lowAt)
                o.send(s.lowBattery,AlertEvent(id:"charge.low",title:t.0,body:t.1,section:"dashboard",thread:"charge"))
            }
        }
        o.memory.wasCharging=b.charging
        let origin=i.limit.origin(lastWritten:i.lastWritten)
        if origin != .unknown {
            // Only a change VibeBattery did not write itself: its own writes move `lastWritten`, and top-up and a yielded hold explain themselves.
            if o.memory.origin == .vibeBattery,origin == .external || origin == .none,o.memory.lastWritten==i.lastWritten,
               i.topUpRequested==nil,i.heatEvent != .yielded {
                let t=NotificationText.limitChanged(origin == .none ? nil:i.limit.limit)
                o.send(s.limitChanged,AlertEvent(id:"charge.limitChanged",title:t.0,body:t.1,section:"dashboard",thread:"charge"))
            }
            if origin == .vibeBattery,let before=o.memory.origin,before != .vibeBattery { o.remove("charge.limitChanged") }
            o.memory.origin=origin;o.memory.lastWritten=i.lastWritten
        }
        if i.limit.supported==true {
            if o.memory.unavailableNotified { o.remove("charge.unavailable") }
            o.memory.supportedSeen=true;o.memory.unavailableNotified=false
        } else if i.limit.supported==false,o.memory.supportedSeen,!o.memory.unavailableNotified {
            o.memory.unavailableNotified=true
            let t=NotificationText.controlUnavailable
            o.send(s.controlUnavailable,AlertEvent(id:"charge.unavailable",title:t.0,body:t.1,section:"dashboard",thread:"charge"))
        }
    }
}
```

Add to `NotificationText`:

```swift
    static func limitReached(_ l:Int) -> (String,String) { ("충전 상한 \(l)% 도달","충전을 멈췄습니다. 어댑터를 연결해 두어도 괜찮습니다.") }
    static func topUpDone(_ p:Int) -> (String,String) { ("완충 끝남 · \(p)%","오래 연결해 두면 배터리에 부담이 됩니다. 원래 상한으로 돌아가는 시점은 macOS가 정합니다.") }
    static func lowBattery(_ p:Int,at:Int) -> (String,String) { ("배터리 \(p)%","설정한 \(at)% 이하로 내려갔습니다.") }
    static func limitChanged(_ l:Int?) -> (String,String) {
        guard let l else { return ("충전 상한이 꺼졌습니다","VibeBattery가 설정한 상한이 해제되어 100%까지 충전됩니다. 대시보드에서 다시 적용하세요.") }
        return ("충전 상한이 \(l)%로 바뀌었습니다","VibeBattery가 설정하지 않은 값입니다. macOS 설정이나 다른 앱이 바꿨을 수 있습니다.")
    }
    static let controlUnavailable=("충전 상한을 제어할 수 없습니다","이 macOS에서 충전 상한 기능을 찾지 못했습니다. 업데이트 후라면 GitHub에서 호환성을 확인하세요.")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `$SW test --disable-xctest --filter NotificationChargeTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/BatteryCore/NotificationPolicy.swift Sources/BatteryCore/NotificationText.swift Tests/BatteryCoreTests/NotificationTestSupport.swift Tests/BatteryCoreTests/NotificationChargeTests.swift
git commit -m "feat: decide charge notifications"
```

---

### Task 3: Protection and heat-hold notifications

**Files:**
- Modify: `Sources/BatteryCore/NotificationPolicy.swift`, `Sources/BatteryCore/NotificationText.swift`
- Test: `Tests/BatteryCoreTests/NotificationProtectTests.swift`

**Interfaces:**
- Consumes: Task 2 `evaluate`, `NT`.
- Produces: `protect`, `heat` steps; constants `hotCooldown`, `hotRearm`, `onBatteryExtra`, `freshTemperature`, `stuckRepeat`, `sensorDelay`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import BatteryCore
struct NotificationProtectTests {
    func hot(_ dt:Double,_ t:Double,ac:Bool=true) -> NotificationInput { NT.input(dt,onAC:ac,temp:t) }
    @Test func highTemperatureFiresOnceAndRearmsAfterCooling() {
        let r=NT.run([hot(0,40),hot(30,41),hot(60,36.9),hot(600,40),hot(1860,40)])
        #expect(NT.ids(r)==[["protect.heat"],[],[],[],["protect.heat"]]);#expect(r[2].removals==["protect.heat"])
        #expect(r[0].events[0].title=="배터리 40.0°C");#expect(r[0].events[0].section=="settings")
    }
    @Test func onBatteryThresholdIsTwoDegreesHigher() {
        #expect(NT.ids(NT.run([hot(0,41,ac:false),hot(30,42,ac:false)]))==[[],["protect.heat"]])
    }
    @Test func staleMissingOrBatterylessTemperatureIsIgnored() {
        var stale=hot(0,50);stale.battery.timestamp=NT.t0-200
        var desktop=hot(0,50);desktop.battery.percent=nil
        var none=hot(0,30);none.battery.temperature=nil
        for x in [stale,desktop,none] { #expect(NT.ids(NT.run([x]))==[[]]) }
    }
    @Test func conflictAnnouncesNewNamesAndClearsWhenGone() {
        var a=NT.input(0);a.conflicts=["AlDente"]
        var b=NT.input(30);b.conflicts=["AlDente"]
        var c=NT.input(60);c.conflicts=["AlDente","batt"]
        let r=NT.run([a,b,c,NT.input(90)])
        #expect(NT.ids(r)==[["protect.conflict"],[],["protect.conflict"],[]])
        #expect(r[0].events[0].body.contains("AlDente"));#expect(r[2].events[0].body.contains("batt"));#expect(r[3].removals==["protect.conflict"])
        #expect(r[0].events[0].section=="dashboard")
    }
    @Test func stuckHoldRepeatsDailyUntilResolved() {
        var a=NT.input(0);a.heatStuckLimit=60
        var b=NT.input(3600);b.heatStuckLimit=60
        var c=NT.input(86400+10);c.heatStuckLimit=60
        let r=NT.run([a,b,c,NT.input(86400+40)])
        #expect(NT.ids(r)==[["heat.stuck"],[],["heat.stuck"],[]]);#expect(r[3].removals==["heat.stuck"])
        #expect(r[0].events[0].body.contains("60%"))
    }
    @Test func heatEventsMapToAlerts() {
        func one(_ e:HeatEvent) -> [AlertEvent] { var i=NT.input(0);i.heatEvent=e;return NT.run([i])[0].events }
        #expect(one(.yielded).map(\.id)==["heat.paused"]);#expect(one(.yielded)[0].duplicatesAppMessage)
        #expect(one(.holdFailed).map(\.id)==["heat.failed"]);#expect(one(.holdFailed)[0].duplicatesAppMessage)
        #expect(one(.held(70)).map(\.id)==["heat.activity"]);#expect(one(.held(70))[0].body.contains("70%"))
        #expect(one(.restored).map(\.id)==["heat.activity"])
        var quiet=NT.all;quiet.heatActivity=false
        var i=NT.input(0);i.heatEvent = .held(70)
        #expect(NT.run([i],quiet)[0].events.isEmpty)
    }
    @Test func missingSensorAnnouncedAfterTenMinutes() {
        func m(_ dt:Double) -> NotificationInput { var i=NT.input(dt,temp:nil);i.heatSensorMissing=true;return i }
        let r=NT.run([m(0),m(300),m(600),m(900),NT.input(930)])
        #expect(NT.ids(r)==[[],[],["heat.sensor"],[],[]]);#expect(r[4].removals==["heat.sensor"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$SW test --disable-xctest --filter NotificationProtectTests`
Expected: FAIL — no `protect.heat` events (empty arrays).

- [ ] **Step 3: Write minimal implementation**

In `NotificationPolicy` add constants and calls (`protect(i,s,&o);heat(i,s,&o)` after `charge(...)`):

```swift
    public static let hotCooldown:TimeInterval=1800, hotRearm=3.0, onBatteryExtra=2.0, freshTemperature:TimeInterval=120
    public static let stuckRepeat:TimeInterval=86400, sensorDelay:TimeInterval=600
    static func protect(_ i:NotificationInput,_ s:NotificationSettings,_ o:inout NotificationOutcome) {
        let b=i.battery,now=i.now,age=now.timeIntervalSince(b.timestamp)
        if b.percent != nil,let t=b.temperature,age >= -5,age<=freshTemperature {
            let limit=b.onAC ? s.hotAt:s.hotAt+onBatteryExtra
            if !o.memory.hotArmed,t<=limit-hotRearm { o.memory.hotArmed=true;o.remove("protect.heat") }
            if o.memory.hotArmed,t>=limit,o.memory.hotSent.map({ now.timeIntervalSince($0)>=hotCooldown }) ?? true {
                o.memory.hotArmed=false;o.memory.hotSent=now
                let x=NotificationText.hot(t,onAC:b.onAC)
                o.send(s.highTemperature,AlertEvent(id:"protect.heat",title:x.0,body:x.1,section:"settings",thread:"protect"))
            }
        }
        let names=Array(Set(i.conflicts)).sorted()
        if names.isEmpty {
            if !o.memory.conflicts.isEmpty { o.remove("protect.conflict") }
        } else if names.contains(where:{ !o.memory.conflicts.contains($0) }) {
            let x=NotificationText.conflict(names)
            o.send(s.conflict,AlertEvent(id:"protect.conflict",title:x.0,body:x.1,section:"dashboard",thread:"protect"))
        }
        o.memory.conflicts=names
    }
    static func heat(_ i:NotificationInput,_ s:NotificationSettings,_ o:inout NotificationOutcome) {
        let now=i.now
        if let l=i.heatStuckLimit {
            if o.memory.stuckSent.map({ now.timeIntervalSince($0)>=stuckRepeat }) ?? true {
                o.memory.stuckSent=now
                let x=NotificationText.heatStuck(l)
                o.send(s.heatProblem,AlertEvent(id:"heat.stuck",title:x.0,body:x.1,section:"settings",thread:"protect"))
            }
        } else if o.memory.stuckSent != nil { o.memory.stuckSent=nil;o.remove("heat.stuck") }
        switch i.heatEvent {
        case .yielded?:
            let x=NotificationText.heatPaused
            o.send(s.heatProblem,AlertEvent(id:"heat.paused",title:x.0,body:x.1,section:"settings",thread:"protect",duplicatesAppMessage:true))
        case .holdFailed?:
            let x=NotificationText.heatFailed
            o.send(s.heatProblem,AlertEvent(id:"heat.failed",title:x.0,body:x.1,section:"settings",thread:"protect",duplicatesAppMessage:true))
        case .held(let p)?:
            let x=NotificationText.heatHeld(p)
            o.send(s.heatActivity,AlertEvent(id:"heat.activity",title:x.0,body:x.1,section:"settings",thread:"protect"))
        case .restored?:
            let x=NotificationText.heatRestored
            o.send(s.heatActivity,AlertEvent(id:"heat.activity",title:x.0,body:x.1,section:"settings",thread:"protect"))
        case nil:break
        }
        if i.heatSensorMissing {
            let since=o.memory.sensorMissingSince ?? now;o.memory.sensorMissingSince=since
            if !o.memory.sensorNotified,now.timeIntervalSince(since)>=sensorDelay {
                o.memory.sensorNotified=true
                let x=NotificationText.heatSensor
                o.send(s.heatProblem,AlertEvent(id:"heat.sensor",title:x.0,body:x.1,section:"settings",thread:"protect"))
            }
        } else {
            if o.memory.sensorNotified { o.remove("heat.sensor") }
            o.memory.sensorMissingSince=nil;o.memory.sensorNotified=false
        }
    }
```

Add to `NotificationText`:

```swift
    static func hot(_ t:Double,onAC:Bool) -> (String,String) {
        (String(format:"배터리 %.1f°C",t),onAC ? "충전 중 온도가 높습니다. 통풍이 되는 곳에 두거나 과열 시 충전 보류를 켜 보세요.":"배터리 온도가 높습니다. 무거운 작업을 줄이고 통풍이 되는 곳에 두세요.")
    }
    static func conflict(_ names:[String]) -> (String,String) { ("다른 충전 관리 앱 감지","\(names.joined(separator:", "))이(가) 감지되어 VibeBattery는 충전 설정을 바꾸지 않습니다.") }
    static func heatStuck(_ l:Int) -> (String,String) { ("과열 보류 복원 실패","충전 상한이 \(l)%로 남아 있습니다. 설정에서 상태를 확인하고 상한을 다시 적용하세요.") }
    static let heatPaused=("과열 보류 멈춤","다른 곳에서 충전 상한이 바뀌어 보류를 멈췄습니다. 설정에서 다시 켜면 재개합니다.")
    static let heatFailed=("과열 보류 실패","충전 상한을 낮추지 못했습니다. 설정에서 상태를 확인하세요.")
    static let heatSensor=("과열 보류가 동작하지 않습니다","배터리 온도를 10분 넘게 읽지 못했습니다.")
    static func heatHeld(_ p:Int) -> (String,String) { ("과열 보류 시작","배터리가 식을 때까지 충전 상한을 \(p)%로 낮췄습니다.") }
    static let heatRestored=("과열 보류 해제","배터리가 식어 원래 충전 상한으로 되돌렸습니다.")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `$SW test --disable-xctest --filter "Notification(Protect|Charge)Tests"`
Expected: PASS (15 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/BatteryCore/NotificationPolicy.swift Sources/BatteryCore/NotificationText.swift Tests/BatteryCoreTests/NotificationProtectTests.swift
git commit -m "feat: decide temperature, conflict and heat-hold notifications"
```

---

### Task 4: Session notifications

**Files:**
- Modify: `Sources/BatteryCore/NotificationPolicy.swift`, `Sources/BatteryCore/NotificationText.swift`
- Test: `Tests/BatteryCoreTests/NotificationSessionTests.swift`

**Interfaces:**
- Consumes: `SessionSummary`, `SessionMark`, `NT`.
- Produces: `sessions` step; constants `lateSession`, `batchLimit`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import BatteryCore
struct NotificationSessionTests {
    let id=UUID()
    func s(_ dt:Double,_ outcome:SessionOutcome = .running,ended:Double?=nil,code:Int32?=nil,released:Bool=false) -> NotificationInput {
        var i=NT.input(dt)
        i.sessions=[SessionSummary(id:id,command:"claude",outcome:outcome,started:NT.t0-3600,ended:ended.map { NT.t0+$0 },exitCode:code,released:released)]
        return i
    }
    var end:String { "session.end.\(id.uuidString)" }
    @Test func endAfterSeenRunningShowsResultAndDuration() {
        let r=NT.run([s(0),s(30,.succeeded,ended:20,code:0)])
        #expect(NT.ids(r)==[[],[end]])
        let e=r[1].events[0];#expect(e.title=="claude 완료");#expect(e.body=="걸린 시간 1시간");#expect(e.section=="sessions");#expect(e.thread=="session")
        #expect(NT.run([s(0),s(30,.failed,ended:20,code:2)])[1].events[0].title=="claude 실패 · 코드 2")
    }
    @Test func protectionReleaseIsAnnouncedThenEndStillArrives() {
        let r=NT.run([s(0),s(30,.detached),s(60,.detached),s(90,.detached,ended:80,code:0)])
        #expect(NT.ids(r)==[[],["session.released.\(id.uuidString)"],[],[end]])
        #expect(r[1].events[0].body.contains("어댑터"));#expect(r[3].events[0].title=="claude 보호 해제 후 종료 · 코드 0")
        #expect(NT.run([s(0),s(30,.expired)])[1].events[0].body.contains("보호 시간"))
    }
    @Test func userReleaseIsNotAnnounced() {
        #expect(NT.ids(NT.run([s(0),s(30,.detached,released:true)]))==[[],[]])
    }
    @Test func cancelledFollowsItsOwnToggle() {
        let steps=[s(0),s(30,.cancelled,ended:20,code:130)]
        #expect(NT.ids(NT.run(steps))[1]==[end]);#expect(NT.run(steps)[1].events[0].title=="claude 취소됨")
        var off=NT.all;off.sessionCancelled=false
        #expect(NT.ids(NT.run(steps,off))[1]==[])
    }
    @Test func sessionsFirstSeenAfterEndingAreAnnouncedOnlyIfRecent() {
        #expect(NT.ids(NT.run([s(0,.succeeded,ended:-300,code:0)]))==[[end]])
        #expect(NT.ids(NT.run([s(0,.succeeded,ended:-1200,code:0)]))==[[]])
        // Already released before the app saw it.
        #expect(NT.ids(NT.run([s(0,.detached),s(30,.detached)]))==[[],[]])
    }
    @Test func moreThanThreeEndingsAreBatched() {
        var a=NT.input(0),b=NT.input(30)
        for _ in 0..<4 {
            let u=UUID()
            a.sessions.append(SessionSummary(id:u,command:"codex",outcome:.running,started:NT.t0-60))
            b.sessions.append(SessionSummary(id:u,command:"codex",outcome:.succeeded,started:NT.t0-60,ended:NT.t0+10,exitCode:0))
        }
        let r=NT.run([a,b]);#expect(NT.ids(r)==[[],["session.batch"]]);#expect(r[1].events[0].title=="작업 4개 종료")
        #expect(r[1].events[0].body=="성공 4 · 그 외 0")
    }
    @Test func memoryKeepsOnlyListedSessions() {
        let r=NT.run([s(0),NT.input(30)])
        #expect(r[0].memory.sessions[id.uuidString] != nil);#expect(r[1].memory.sessions.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$SW test --disable-xctest --filter NotificationSessionTests`
Expected: FAIL — no session events.

- [ ] **Step 3: Write minimal implementation**

In `NotificationPolicy` add `sessions(i,s,&o)` after `heat(...)` in `evaluate`, and:

```swift
    public static let lateSession:TimeInterval=600, batchLimit=3
    static func sessions(_ i:NotificationInput,_ s:NotificationSettings,_ o:inout NotificationOutcome) {
        var ended:[SessionSummary]=[],marks:[String:SessionMark]=[:]
        for x in i.sessions {
            let key=x.id.uuidString
            guard var m=o.memory.sessions[key] else {
                // First sight: only a recent ending is news; an already released protection is not.
                if let e=x.ended {
                    let age=i.now.timeIntervalSince(e)
                    if age>=0,age<=lateSession { ended.append(x) }
                    marks[key]=SessionMark(ended:true,released:true)
                } else { marks[key]=SessionMark(released:x.outcome != .running) }
                continue
            }
            if x.ended==nil,!m.released,x.outcome != .running {
                m.released=true
                if x.outcome == .expired || (x.outcome == .detached && !x.released) {
                    let t=NotificationText.protectionReleased(x)
                    o.send(s.protectionReleased,AlertEvent(id:"session.released.\(key)",title:t.0,body:t.1,section:"sessions",thread:"session"))
                }
            }
            if x.ended != nil,!m.ended { m.ended=true;m.released=true;ended.append(x) }
            marks[key]=m
        }
        o.memory.sessions=marks
        let wanted=ended.filter { $0.outcome == .cancelled ? s.sessionCancelled:s.sessionEnded }
        if wanted.count>batchLimit {
            let t=NotificationText.sessionBatch(wanted)
            o.send(true,AlertEvent(id:"session.batch",title:t.0,body:t.1,section:"sessions",thread:"session"))
        } else {
            for x in wanted {
                let t=NotificationText.sessionEnd(x)
                o.send(true,AlertEvent(id:"session.end.\(x.id.uuidString)",title:t.0,body:t.1,section:"sessions",thread:"session"))
            }
        }
    }
```

Add to `NotificationText`:

```swift
    static func sessionEnd(_ x:SessionSummary) -> (String,String) {
        let name=x.command.isEmpty ? "작업":x.command,code=x.exitCode.map { " · 코드 \($0)" } ?? ""
        let result:String
        switch x.outcome {
        case .cancelled:result="취소됨"
        case .detached,.expired:result="보호 해제 후 종료"+code
        default:result=x.exitCode==0 ? "완료":"실패"+code
        }
        return ("\(name) \(result)","걸린 시간 \(duration((x.ended ?? x.started).timeIntervalSince(x.started)))")
    }
    static func sessionBatch(_ xs:[SessionSummary]) -> (String,String) {
        let ok=xs.filter { $0.exitCode==0 && $0.outcome != .cancelled }.count
        return ("작업 \(xs.count)개 종료","성공 \(ok) · 그 외 \(xs.count-ok)")
    }
    static func protectionReleased(_ x:SessionSummary) -> (String,String) {
        let why=x.outcome == .expired ? "보호 시간이 끝났습니다.":"어댑터가 분리되었습니다."
        return ("\(x.command.isEmpty ? "작업":x.command) 잠자기 방지 해제","\(why) 작업은 계속되지만 맥이 잠들 수 있습니다.")
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `$SW test --disable-xctest --filter "Notification(Session|Protect|Charge)Tests"`
Expected: PASS (22 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/BatteryCore/NotificationPolicy.swift Sources/BatteryCore/NotificationText.swift Tests/BatteryCoreTests/NotificationSessionTests.swift
git commit -m "feat: decide vibe-coding session notifications"
```

---

### Task 5: Health notifications and common rules

**Files:**
- Modify: `Sources/BatteryCore/NotificationPolicy.swift`, `Sources/BatteryCore/NotificationText.swift`
- Test: `Tests/BatteryCoreTests/NotificationHealthTests.swift`

**Interfaces:**
- Consumes: `SleepEvent`, `Suggestion`, `UsageSummary`, `HealthText.stress`, `HealthText.hours`.
- Produces: `health` step; constants `suggestionRepeat`, `weeklyHour`; `week(_:_:) -> (key:String,opens:Date)?`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import BatteryCore
struct NotificationHealthTests {
    func sleep(hours:Double,from:Int,to:Int) -> SleepEvent {
        var a=BatterySnapshot();a.timestamp=NT.t0-hours*3600;a.percent=from
        var b=BatterySnapshot();b.timestamp=NT.t0;b.percent=to
        return SleepEvent(before:a,after:b)
    }
    @Test func highSleepDrainAnnouncedOnWake() {
        var i=NT.input(0);i.wake=sleep(hours:2,from:80,to:74)
        let r=NT.run([i]);#expect(NT.ids(r)==[["health.sleep"]]);#expect(r[0].events[0].section=="health")
        #expect(r[0].events[0].body.contains("3.0%"))
        var calm=NT.input(0);calm.wake=sleep(hours:8,from:80,to:78)
        #expect(NT.ids(NT.run([calm]))==[[]])
    }
    @Test func suggestionsRepeatAtMostWeekly() {
        func g(_ dt:Double) -> NotificationInput { var i=NT.input(dt);i.suggestions=[Suggestion(kind:.chargeLimit,message:"상한 80% 권장")];return i }
        let r=NT.run([g(0),g(86400),g(7*86400)])
        #expect(NT.ids(r)==[["health.suggestion.chargeLimit"],[],["health.suggestion.chargeLimit"]])
        #expect(r[0].events[0].body=="상한 80% 권장")
    }
    @Test func weeklySummaryOncePerWeekAfterMondayNine() {
        func w(_ dt:Double) -> NotificationInput { var i=NT.input(dt);var u=UsageSummary();u.observed=3600;u.soc95=7200;i.week=u;return i }
        let nextMonday9=Double(7*86400-(14*3600+13*60+20)+9*3600)
        let r=NT.run([w(0),w(86400),w(nextMonday9-60),w(nextMonday9)])
        #expect(NT.ids(r)==[["health.weekly"],[],[],["health.weekly"]])
        #expect(r[0].memory.weekKey=="2026-W39");#expect(r[3].memory.weekKey=="2026-W40")
        #expect(r[0].events[0].body.contains("2.0시간"))
        var empty=NT.input(0);empty.week=UsageSummary()
        #expect(NT.ids(NT.run([empty]))==[[]])
    }
    @Test func disabledEventsStillAdvanceMemory() {
        var off=NT.all;off.highTemperature=false
        let first=NotificationPolicy.evaluate(NT.input(0,temp:41),settings:off,memory:NotificationMemory())
        #expect(first.events.isEmpty);#expect(!first.memory.hotArmed)
        #expect(NotificationPolicy.evaluate(NT.input(30,temp:41),settings:NT.all,memory:first.memory).events.isEmpty)
    }
    @Test func timestampsFromTheFutureCountAsExpired() {
        var m=NotificationMemory();m.hotSent=NT.t0+86400
        #expect(NT.ids(NT.run([NT.input(0,temp:41)],memory:m))==[["protect.heat"]])
        var g=NotificationMemory();g.suggestionSent["chargeLimit"]=NT.t0+86400
        var i=NT.input(0);i.suggestions=[Suggestion(kind:.chargeLimit,message:"x")]
        #expect(NT.ids(NT.run([i],memory:g))==[["health.suggestion.chargeLimit"]])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$SW test --disable-xctest --filter NotificationHealthTests`
Expected: FAIL — health events missing (`timestampsFromTheFutureCountAsExpired`'s heat half and `disabledEventsStillAdvanceMemory` already pass through Tasks 1–3; the health tests fail).

- [ ] **Step 3: Write minimal implementation**

In `NotificationPolicy` add `health(i,s,&o)` after `sessions(...)` in `evaluate`, and:

```swift
    public static let suggestionRepeat:TimeInterval=7*86400, weeklyHour=9
    static func health(_ i:NotificationInput,_ s:NotificationSettings,_ o:inout NotificationOutcome) {
        let now=i.now
        if let w=i.wake,w.isHigh,let r=w.drainPerHour {
            let t=NotificationText.sleepDrain(r,w.end.timeIntervalSince(w.start))
            o.send(s.sleepDrain,AlertEvent(id:"health.sleep",title:t.0,body:t.1,section:"health",thread:"health"))
        }
        for g in i.suggestions {
            let key=g.kind.rawValue
            guard o.memory.suggestionSent[key].map({ now.timeIntervalSince($0)>=suggestionRepeat }) ?? true else { continue }
            o.memory.suggestionSent[key]=now
            o.send(s.suggestions,AlertEvent(id:"health.suggestion.\(key)",title:"배터리 관리 제안",body:g.message,section:"health",thread:"health"))
        }
        if let u=i.week,u.observed>0,let w=week(now,i.calendar),now>=w.opens,o.memory.weekKey != w.key {
            o.memory.weekKey=w.key
            let t=NotificationText.weekly(u)
            o.send(s.weeklySummary,AlertEvent(id:"health.weekly",title:t.0,body:t.1,section:"health",thread:"health"))
        }
    }
    /// ISO week key and that week's Monday 09:00 in the calendar's time zone.
    static func week(_ now:Date,_ cal:Calendar) -> (key:String,opens:Date)? {
        var c=Calendar(identifier:.iso8601);c.timeZone=cal.timeZone
        guard let start=c.dateInterval(of:.weekOfYear,for:now)?.start,
              let opens=c.date(bySettingHour:weeklyHour,minute:0,second:0,of:start) else { return nil }
        let w=c.dateComponents([.yearForWeekOfYear,.weekOfYear],from:now)
        guard let y=w.yearForWeekOfYear,let n=w.weekOfYear else { return nil }
        return (String(format:"%04d-W%02d",y,n),opens)
    }
```

Add to `NotificationText`:

```swift
    static func sleepDrain(_ rate:Double,_ seconds:TimeInterval) -> (String,String) {
        ("잠자기 중 배터리가 많이 줄었습니다",String(format:"%@ 동안 시간당 %.1f%%. 잠자기를 막거나 깨우는 앱이 있는지 확인해 보세요.",duration(seconds),rate))
    }
    static func weekly(_ u:UsageSummary) -> (String,String) { ("주간 배터리 요약","최근 7일 잔량 95% 이상 \(HealthText.hours(u.soc95)) · \(HealthText.stress(u))") }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `$SW test --disable-xctest --filter Notification`
Expected: PASS (35 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/BatteryCore/NotificationPolicy.swift Sources/BatteryCore/NotificationText.swift Tests/BatteryCoreTests/NotificationHealthTests.swift
git commit -m "feat: decide health notifications and weekly summary"
```

---

### Task 6: Notification memory store

**Files:**
- Create: `Sources/BatteryPlatform/NotificationStore.swift`
- Modify: `Sources/BatteryPlatform/SessionStore.swift` (AppPaths)
- Test: `Tests/BatteryCoreTests/NotificationStoreTests.swift`

**Interfaces:**
- Consumes: `JSONFile`, `NotificationMemory`.
- Produces: `NotificationStore(url:)` with `read() -> NotificationMemory`, `@discardableResult save(_:) throws -> Bool`; `AppPaths.notify`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import BatteryCore
@testable import BatteryPlatform
struct NotificationStoreTests {
    func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("vb-notify-\(UUID().uuidString)/notify.json") }
    @Test func savesPrivatelyAndOnlyWhenChanged() throws {
        let u=url();let store=NotificationStore(url:u)
        var m=store.read();#expect(m==NotificationMemory())
        m.hotArmed=false;#expect(try store.save(m))
        #expect(try FileManager.default.attributesOfItem(atPath:u.path)[.posixPermissions] as? Int==0o600)
        m.evaluated=Date();m.wasCharging=true
        #expect(try store.save(m)==false)
        #expect(NotificationStore(url:u).read().hotArmed==false)
    }
    @Test func corruptMemoryIsMovedAside() throws {
        let u=url();try FileManager.default.createDirectory(at:u.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("{oops".utf8).write(to:u)
        #expect(NotificationStore(url:u).read()==NotificationMemory())
        #expect(try FileManager.default.contentsOfDirectory(atPath:u.deletingLastPathComponent().path).contains { $0.hasPrefix("notify.json.corrupt-") })
    }
    @Test func pathLivesInDataDirectory() { #expect(AppPaths.notify.lastPathComponent=="notify.json") }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$SW test --disable-xctest --filter NotificationStoreTests`
Expected: FAIL — `NotificationStore` not found.

- [ ] **Step 3: Write minimal implementation**

`Sources/BatteryPlatform/NotificationStore.swift`:

```swift
import Foundation
import BatteryCore
/// `notify.json`: written only when the saved fields change, not on every refresh.
public final class NotificationStore {
    let file:JSONFile<NotificationMemory>
    private var saved:Data?
    public init(url:URL) { file=JSONFile(url:url) }
    public func read() -> NotificationMemory { let m=file.load() ?? NotificationMemory();saved=Self.key(m);return m }
    @discardableResult public func save(_ m:NotificationMemory) throws -> Bool {
        let k=Self.key(m);guard k != saved else { return false }
        try file.save(m);saved=k;return true
    }
    /// Sorted keys so dictionary order cannot cause a rewrite.
    static func key(_ m:NotificationMemory) -> Data? { let e=JSONEncoder();e.outputFormatting = .sortedKeys;return try? e.encode(m) }
}
```

In `AppPaths` add:

```swift
    public static var notify:URL { directory.appendingPathComponent("notify.json") }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `$SW test --disable-xctest --filter NotificationStoreTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/BatteryPlatform/NotificationStore.swift Sources/BatteryPlatform/SessionStore.swift Tests/BatteryCoreTests/NotificationStoreTests.swift
git commit -m "feat: store notification memory privately"
```

---

### Task 7: App delivery, routing, settings and docs

**Files:**
- Create: `Sources/VibeBattery/Notifier.swift`
- Modify: `Sources/VibeBattery/App.swift`, `Sources/VibeBattery/AppModel.swift`, `Sources/VibeBattery/SettingsView.swift`, `Sources/VibeBattery/HealthView.swift`
- Modify: `README.md`, `docs/COMPATIBILITY.md`, `docs/VALIDATION.md`

**Interfaces:**
- Consumes: everything above; `ChargeController.record`, `heatStep` result, `SessionStore.isReleased`.
- Produces: `NotificationAccess`, `NotificationSink`, `SystemNotificationSink`, `NoNotificationSink`, `NotificationRuntime.bundled/makeSink()`, `NotificationRouter.shared`, `AppDelegate`; `AppModel.notify(wake:)`, `requestNotifications()`, `sendTestNotification()`, `openNotificationSettings()`, `show(_:)`, `openMain`.

- [ ] **Step 1: Write `Notifier.swift`**

```swift
import Foundation
import AppKit
import UserNotifications
import BatteryCore
enum NotificationAccess { case allowed, denied, notAsked, unavailable }
@MainActor protocol NotificationSink: AnyObject {
    func deliver(_ e:AlertEvent)
    func remove(_ ids:[String])
    func access(_ done:@escaping @MainActor (NotificationAccess)->Void)
    func request(_ done:@escaping @MainActor (NotificationAccess)->Void)
}
/// Used when the binary runs outside an .app bundle, where UserNotifications would abort the process.
final class NoNotificationSink: NotificationSink {
    func deliver(_ e:AlertEvent) {}
    func remove(_ ids:[String]) {}
    func access(_ done:@escaping @MainActor (NotificationAccess)->Void) { done(.unavailable) }
    func request(_ done:@escaping @MainActor (NotificationAccess)->Void) { done(.unavailable) }
}
final class SystemNotificationSink: NotificationSink {
    private let center=UNUserNotificationCenter.current()
    func deliver(_ e:AlertEvent) {
        let c=UNMutableNotificationContent()
        c.title=e.title;c.body=e.body;c.threadIdentifier=e.thread;c.userInfo=["section":e.section];c.sound = .default
        center.add(UNNotificationRequest(identifier:e.id,content:c,trigger:nil)) { _ in }
    }
    func remove(_ ids:[String]) { center.removeDeliveredNotifications(withIdentifiers:ids) }
    func access(_ done:@escaping @MainActor (NotificationAccess)->Void) {
        center.getNotificationSettings { s in
            let a:NotificationAccess
            switch s.authorizationStatus {
            case .authorized,.provisional:a = .allowed
            case .denied:a = .denied
            default:a = .notAsked
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { done(a) } }
        }
    }
    func request(_ done:@escaping @MainActor (NotificationAccess)->Void) {
        center.requestAuthorization(options:[.alert,.sound]) { [weak self] _,_ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.access(done) } }
        }
    }
}
enum NotificationRuntime {
    static var bundled:Bool { Bundle.main.bundleURL.pathExtension=="app" && Bundle.main.bundleIdentifier != nil }
    @MainActor static func makeSink() -> NotificationSink { bundled ? SystemNotificationSink():NoNotificationSink() }
}
/// Receives notification clicks, including the one that launched the app, and shows foreground notifications.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared=NotificationRouter()
    @MainActor var open:((String)->Void)? { didSet { if let p=pending,let open { pending=nil;open(p) } } }
    @MainActor private var pending:String?
    @MainActor func route(_ section:String) { if let open { open(section) } else { pending=section } }
    func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler completionHandler:@escaping (UNNotificationPresentationOptions)->Void) {
        completionHandler([.banner,.list,.sound])
    }
    func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completionHandler:@escaping ()->Void) {
        let section=AlertEvent.route(response.notification.request.content.userInfo["section"])
        DispatchQueue.main.async { MainActor.assumeIsolated { NotificationRouter.shared.route(section) };completionHandler() }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification:Notification) {
        if NotificationRuntime.bundled { UNUserNotificationCenter.current().delegate=NotificationRouter.shared }
    }
}
```

- [ ] **Step 2: Wire `App.swift`**

Add `@NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate` to `VibeBatteryApp`, and replace the MenuBarExtra label with `MenuLabel().environmentObject(model)`:

```swift
/// Always rendered, so it is where the app keeps a way to reopen the window for notification clicks.
struct MenuLabel:View {
    @EnvironmentObject var model:AppModel
    @Environment(\.openWindow) var openWindow
    var body:some View {
        Label("\(model.battery.percent.map(String.init) ?? "—")%",systemImage:model.battery.onAC ? "bolt.batteryblock":"battery.75percent")
            .onAppear { model.openMain={ openWindow(id:"main") } }
    }
}
```

- [ ] **Step 3: Wire `AppModel.swift`**

Properties:
```swift
    @Published var notificationAccess=NotificationAccess.unavailable
    var openMain:(()->Void)?
    private let notifier=NotificationRuntime.makeSink()
    private let notificationStore=NotificationStore(url:AppPaths.notify)
    private lazy var notificationMemory=notificationStore.read()
    private var pendingHeatEvent:HeatEvent?
```
In `refreshCharge()` after `lastHeatAction=step.action`:
```swift
        var failed=false;if case .failure?=step.result { failed=true }
        if let e=HeatEvent.from(action:step.action,failed:failed) { pendingHeatEvent=e }
```
`refresh()` gains `wake:SleepEvent?=nil` and ends with `notify(wake:wake)`. `didWake()` becomes:
```swift
    func didWake() {
        var wake:SleepEvent?
        if let s=sleepStart, preferences.backgroundHistory {
            let e=SleepEvent(before:s,after:BatteryReader.read());wake=e
            do { try sleepStore.append(e);sleeps=sleepStore.read() } catch { message=error.localizedDescription }
        }
        sleepStart=nil;refresh(wake:wake)
    }
```
New methods:
```swift
    func notify(wake:SleepEvent?=nil) {
        var i=NotificationInput(now:Date(),battery:battery)
        let r=chargeController.record
        i.limit=charge;i.lastWritten=r.lastWritten;i.topUpRequested=r.topUpRequested
        i.heatEnabled=preferences.heat.enabled;i.heatHolding=r.heat.holdLimit != nil
        i.heatStuckLimit=r.heatPaused ? r.heat.holdLimit:nil
        i.heatSensorMissing=preferences.heat.enabled && lastHeatAction == .sensorUnavailable
        i.heatEvent=pendingHeatEvent;pendingHeatEvent=nil
        i.conflicts=chargeConflicts.map(\.name)
        let store=AppPaths.sessions
        i.sessions=sessions.map { SessionSummary(id:$0.id,command:$0.command,outcome:$0.outcome,started:$0.started,ended:$0.ended,exitCode:$0.exitCode,released:store.isReleased($0.id)) }
        i.wake=wake;i.suggestions=healthReport?.suggestions ?? [];i.week=healthReport?.week
        let o=NotificationPolicy.evaluate(i,settings:preferences.notifications,memory:notificationMemory)
        notificationMemory=o.memory
        // A failed write only risks one repeated alert; the next refresh retries.
        try? notificationStore.save(o.memory)
        if !o.removals.isEmpty { notifier.remove(o.removals) }
        // NSApp may not exist yet during the first refresh from init.
        let front=NSApplication.shared.isActive
        for e in o.events where !(front && e.duplicatesAppMessage) { notifier.deliver(e) }
    }
    func checkNotifications() { notifier.access { [weak self] in self?.notificationAccess=$0 } }
    func requestNotifications() { notifier.request { [weak self] in self?.notificationAccess=$0 } }
    func sendTestNotification() {
        notifier.deliver(AlertEvent(id:"test",title:"VibeBattery 테스트 알림",body:"알림이 정상적으로 표시됩니다. 누르면 설정 화면이 열립니다.",section:"settings",thread:"test"))
    }
    func openNotificationSettings() { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.notifications")!) }
    func show(_ s:String) { section=s;openMain?();NSApp.activate(ignoringOtherApps:true) }
```
In `init()` after `checkHelper()`:
```swift
        checkNotifications()
        NotificationRouter.shared.open={ [weak self] in self?.show($0) }
```

- [ ] **Step 4: Settings card and health toggle**

In `SettingsView` add after the heat card:
```swift
        Card {
            Text("알림").font(.headline)
            HStack {
                Text(accessText).foregroundStyle(.secondary);Spacer()
                if model.notificationAccess == .notAsked { Button("알림 허용") { model.requestNotifications() } }
                if model.notificationAccess == .denied { Button("시스템 설정 열기") { model.openNotificationSettings() } }
                Button("테스트 알림 보내기") { model.sendTestNotification() }.disabled(model.notificationAccess != .allowed)
            }
            Text("충전 상태").font(.subheadline.weight(.semibold))
            flag("충전 상한 도달","충전 중 상한에 닿아 충전이 멈추면",\.limitReached)
            flag("완충 끝남","한 번 완충이 99% 이상이 되면",\.topUpDone)
            flag("배터리 부족","배터리 사용 중 아래 기준 이하로 내려가면",\.lowBattery)
            Stepper("배터리 부족 기준 \(model.preferences.notifications.lowAt)%",value:$model.preferences.notifications.lowAt,in:NotificationSettings.lowRange,step:5).onChange(of:model.preferences.notifications.lowAt) { _,_ in model.savePreferences() }
            flag("충전 상한이 꺼지거나 바뀜","VibeBattery가 설정한 상한을 다른 곳에서 바꾸면",\.limitChanged)
            flag("충전 제어 불가","macOS가 충전 상한 기능을 더 이상 제공하지 않으면",\.controlUnavailable)
            Text("보호 경고").font(.subheadline.weight(.semibold))
            flag("배터리 고온","아래 기준 이상(배터리 사용 중에는 +2°C)이면",\.highTemperature)
            Stepper("고온 기준(충전 중) \(Int(model.preferences.notifications.hotAt))°C",value:$model.preferences.notifications.hotAt,in:NotificationSettings.hotRange,step:1).onChange(of:model.preferences.notifications.hotAt) { _,_ in model.savePreferences() }
            flag("다른 충전 관리 앱 감지","AlDente 등이 감지되어 변경을 막으면",\.conflict)
            flag("과열 보류 문제","복원 실패, 멈춤, 적용 실패, 온도 센서 없음",\.heatProblem)
            flag("과열 보류 시작·해제","보류를 걸거나 풀 때마다",\.heatActivity)
            Text("바이브 코딩").font(.subheadline.weight(.semibold))
            flag("작업 종료","실행 파일 이름과 걸린 시간만 표시",\.sessionEnded)
            flag("작업 취소","Ctrl‑C 등으로 취소한 작업",\.sessionCancelled)
            flag("잠자기 방지 해제","어댑터 분리나 시간 만료로 보호가 풀리면",\.protectionReleased)
            Text("건강 분석").font(.subheadline.weight(.semibold))
            flag("잠자기 중 배터리 소모","깨어났을 때 시간당 소모가 크면",\.sleepDrain)
            flag("새 제안","같은 제안은 7일에 한 번",\.suggestions)
            flag("주간 요약","월요일 09:00 이후 첫 측정 때",\.weeklySummary)
            Text("앱이 실행 중일 때만 알리며 최대 2분 늦을 수 있습니다. 집중 모드에서는 가려질 수 있고, 잠금 화면 미리보기는 macOS 알림 설정을 따릅니다.").font(.caption).foregroundStyle(.secondary)
        }
```
with helpers in `SettingsView`:
```swift
    var accessText:String {
        switch model.notificationAccess {
        case .allowed:return "알림 허용됨"
        case .denied:return "알림이 거부되어 있습니다"
        case .notAsked:return "알림 권한을 아직 묻지 않았습니다"
        case .unavailable:return "개발 실행이라 알림을 쓸 수 없습니다"
        }
    }
    func flag(_ title:String,_ detail:String,_ key:WritableKeyPath<NotificationSettings,Bool>) -> some View {
        Toggle(isOn:Binding(get:{ model.preferences.notifications[keyPath:key] },set:{ model.preferences.notifications[keyPath:key]=$0;model.savePreferences() })) {
            VStack(alignment:.leading,spacing:2) { Text(title);Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
```
Also call `model.checkNotifications()` from `.onAppear` on the card, and in the features card change "개발 예정: 알림, 일정·단축어, MagSafe LED." to "알림: 충전·보호·바이브 코딩·건강 이벤트를 이벤트별로 켜고 끔. 개발 예정: 일정·단축어, MagSafe LED."

In `HealthView` suggestions card, after the `ForEach`:
```swift
                Toggle("새 제안이 생기면 알림 (같은 제안은 7일에 한 번)",isOn:Binding(get:{ model.preferences.notifications.suggestions },set:{ model.preferences.notifications.suggestions=$0;model.savePreferences() }))
```

- [ ] **Step 5: Build, full test, smoke**

Run: `$SW build 2>&1 | tail -5` → Expected: `Build complete!` with no new warnings in the notification files.
Run: `$SW test --disable-xctest 2>&1 | tail -3` → Expected: all tests pass (100 + 38).
Smoke: build the release app into the scratchpad with `VB_SWIFT=$SW VB_OUTPUT_DIR=<scratch>/dist scripts/build-app.sh`, launch `<scratch>/dist/VibeBattery.app/Contents/MacOS/VibeBattery` with `VIBEBATTERY_DATA_DIR=<scratch>/data` in the background for ~40 s, then terminate that PID only. Expected: process stays alive, no permission prompt is requested at launch (no `requestAuthorization` call path at startup), `<scratch>/data/notify.json` exists with mode 0600. Also run the debug binary `.build/debug/VibeBattery` the same way for ~10 s: expected alive (no crash from UserNotifications outside a bundle).

- [ ] **Step 6: Docs**

- README "현재 기능" bullet: `- 로컬 알림: 충전 상한 도달·꺼짐·외부 변경, 완충 끝남, 배터리 부족, 고온, 과열 보류 문제, 다른 충전 관리 앱, 바이브 코딩 작업 종료·잠자기 방지 해제, 잠자기 중 소모, 새 제안, 주간 요약. 이벤트별로 켜고 끄며 같은 상황은 한 번만 알림(앱 실행 중에만)`
- COMPATIBILITY: add row `| Notifications | Local UNUserNotificationCenter alerts decided by a pure, tested policy; per-event toggles, one alert per condition with persisted re-arm state, clicks open an allow-listed screen. Only while the app runs (up to ~2 min late under App Nap); Time Sensitive delivery is unavailable with ad-hoc signing. Permission prompt, delivery and click routing await on-device check |` and remove nothing else.
- VALIDATION: add section `## Notifications (2026-10-20)` listing the test count, the smoke results, and the pending on-device checks (permission prompt under ad-hoc signing, foreground/background delivery, click routing, permission kept after rebuild, top-up condition).

- [ ] **Step 7: Commit**

```bash
git add Sources/VibeBattery README.md docs/COMPATIBILITY.md docs/VALIDATION.md
git commit -m "feat: deliver local notifications with per-event settings"
```
