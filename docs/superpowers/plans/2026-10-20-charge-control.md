# Charge Control Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace AlDente Pro's charge limiting on macOS 27 with a verified VibeBattery charge-control engine: limit 50–100%, one-time full charge, heat hold, conflict detection, and a minimal root helper.

**Architecture:** Pure decisions live in `BatteryCore` (commands, origin, heat-hold hysteresis, helper authorization). `BatteryPlatform` adds a PowerUI bridge (user-level 80–100%), a stateful `ChargeController` that blocks on conflicts, routes sub-80 limits to an XPC root helper, and verifies every write by reading back. A new `VBChargeHelper` executable accepts only `setLimit(50…100)` and `readState()`. The SwiftUI app shows a charge-control card and runs the heat-hold loop on its 30 s refresh.

**Tech Stack:** Swift 6 toolchain in Swift 5 language mode, macOS 15+, SwiftUI/AppKit, Objective-C (PowerUI bridge in `MacBridge`), NSXPCConnection, CFPreferences, ServiceManagement (`SMAppService.mainApp`), Swift Testing.

**Spec:** ../specs/2026-10-20-charge-control-design.md (parent: ../specs/2026-10-18-design.md)

## Global Constraints

- Target: MacBook Pro M4 Pro (Mac16,8), macOS 27.0.1, firmware 20457.1.29. No claims for other machines.
- Limit range 50–100 integer. 80–100 via PowerUI as the user; below 80 only through the root helper.
- Never cut adapter power (`CHIE`), never force discharge, never write SMC keys.
- First launch reads and shows the current limit; it never changes it automatically. Heat hold is off by default.
- Every write is verified by reading back; a mismatch shows "적용 실패" and is never retried automatically.
- If another charge manager (AlDente, batt) is running or installed, every write is blocked; VibeBattery never quits or deletes other apps.
- Heat hold defaults: hold 35°C, resume 32°C, resume after 5 min stable, stale temperature after 120 s, only when SoC ≥ 50%. Labelled as a conservative design value, not an Apple safety threshold.
- The helper exposes no generic defaults/command interface. It writes only `mclLimitValue` (and `MCLFeatureState` only when absent) in `com.apple.smartcharging.topoffprotection`, then posts `com.apple.smartcharging.defaultschanged`.
- Automated tests and smoke runs must never change this Mac's real charge limit.
- UI copy is Korean. Commit messages are English, conventional style, and end with the attribution lines from the session.
- Local build/test command: `SWIFT=/Users/youngmin/Documents/Codex/2026-10-18/a/work/swift-local` then `$SWIFT test --disable-xctest`. `work/` is local-only and never committed.
- Tasks 1–7 can run remotely. Task 8 needs the user at the Mac (sudo, AlDente removal); stop and ask before it.

## Review Focus

- A test or smoke command that passes a valid limit (80–100) to the real PowerUI bridge would change the user's real charge limit — only out-of-range values may touch `vb_mcl_set_limit` in tests (Task 3 test pins the range guard).
- App restart during a heat hold: the persisted hold must still restore the user's limit, and an intervening external change must never be overwritten (Task 4 `heatHoldSurvivesRestartAndRestoresUserLimit`, Task 1 `externalChangeDuringHoldIsNeverOverwritten`).
- An existing `preferences.json` written before this feature must still load with the user's hours/cleanup choices (Task 6 `legacyPreferencesKeepChoices`).
- VibeBattery's own helper files must never be reported as a conflicting controller, while a leftover AlDente daemon plist after the app is deleted must still block writes (Task 2 tests).
- A failed heat-hold write must not loop every 30 s against macOS or another controller (Task 4 `failedHeatHoldPausesInsteadOfRetrying`).

---

### Task 1: Charge commands, origin, and heat-hold policy (pure)

**Files:**
- Create: `Sources/BatteryCore/ChargeControl.swift`
- Test: `Tests/BatteryCoreTests/ChargeControlTests.swift`

**Interfaces:**
- Consumes: `BatterySnapshot` (`timestamp`, `percent`, `temperature`, `onAC`, `charging`) from `Sources/BatteryCore/BatterySnapshot.swift`.
- Produces:
  - `enum ChargeCommand: Equatable, Sendable { case setLimit(Int), clearLimit, startTopUp, endTopUp }`, `static let range = 50...100`, `static let userFloor = 80`, `var isValid: Bool`, `var requiresHelper: Bool`
  - `enum LimitOrigin: String, Codable, Sendable { case vibeBattery, external, none, unknown }`
  - `struct ChargeLimitState: Codable, Equatable, Sendable { var supported: Bool?; var enabled: Bool?; var limit: Int? }`, `init(supported:enabled:limit:)`, `func origin(lastWritten: Int?) -> LimitOrigin`, `func matches(_: ChargeCommand) -> Bool?`
  - `struct HeatSettings: Codable, Equatable, Sendable { var enabled = false; var holdAt = 35.0; var resumeAt = 32.0; mutating func validate() }`
  - `struct HeatState: Codable, Equatable, Sendable { var holdLimit: Int?; var userLimit: Int?; var coolSince: Date? }`
  - `enum HeatAction: Equatable, Sendable { case none, hold(Int), restore(ChargeCommand), cannotHold, sensorUnavailable }`
  - `enum HeatHoldPolicy { static func step(snapshot:limit:settings:state:helperAvailable:now:) -> HeatAction }`

- [ ] **Step 1: Write the failing tests**

`Tests/BatteryCoreTests/ChargeControlTests.swift`:

```swift
import Testing
import Foundation
@testable import BatteryCore
struct ChargeControlTests {
    func hot(_ t:Double?,percent:Int=85,at now:Date) -> BatterySnapshot {
        var b=BatterySnapshot();b.timestamp=now;b.temperature=t;b.percent=percent;b.onAC=true;b.charging=true;return b
    }
    let on:HeatSettings={ var s=HeatSettings();s.enabled=true;return s }()
    let limit90=ChargeLimitState(supported:true,enabled:true,limit:90)
    @Test func commandRangeAndHelperRouting() {
        #expect(ChargeCommand.setLimit(50).isValid);#expect(ChargeCommand.setLimit(100).isValid)
        #expect(!ChargeCommand.setLimit(49).isValid);#expect(!ChargeCommand.setLimit(101).isValid)
        #expect(ChargeCommand.setLimit(79).requiresHelper);#expect(!ChargeCommand.setLimit(80).requiresHelper)
        #expect(!ChargeCommand.startTopUp.requiresHelper);#expect(ChargeCommand.clearLimit.isValid)
    }
    @Test func originDistinguishesOwnExternalAndUnknown() {
        #expect(ChargeLimitState(supported:true,enabled:true,limit:79).origin(lastWritten:nil) == .external)
        #expect(ChargeLimitState(supported:true,enabled:true,limit:80).origin(lastWritten:80) == .vibeBattery)
        #expect(ChargeLimitState(supported:true,enabled:false,limit:80).origin(lastWritten:80) == LimitOrigin.none)
        #expect(ChargeLimitState().origin(lastWritten:80) == .unknown)
        #expect(ChargeLimitState(supported:false,enabled:true,limit:80).origin(lastWritten:80) == .unknown)
    }
    @Test func readbackMatchingPerCommand() {
        let s=ChargeLimitState(supported:true,enabled:true,limit:85)
        #expect(s.matches(.setLimit(85))==true);#expect(s.matches(.setLimit(80))==false)
        #expect(s.matches(.clearLimit)==false);#expect(s.matches(.endTopUp)==true);#expect(s.matches(.startTopUp)==nil)
    }
    @Test func heatSettingsRejectInvertedOrNonFiniteThresholds() {
        var s=HeatSettings();s.holdAt = .nan;s.resumeAt = .infinity;s.validate()
        #expect(s.holdAt==35);#expect(s.resumeAt==32)
        s.holdAt=31;s.resumeAt=33;s.validate();#expect(s.resumeAt==30)
    }
    @Test func holdsAtCurrentChargeAndResumesAfterStableCooling() {
        let t0=Date();var st=HeatState()
        #expect(HeatHoldPolicy.step(snapshot:hot(36,at:t0),limit:limit90,settings:on,state:&st,helperAvailable:false,now:t0) == .hold(85))
        let held=ChargeLimitState(supported:true,enabled:true,limit:85)
        #expect(HeatHoldPolicy.step(snapshot:hot(31,at:t0+60),limit:held,settings:on,state:&st,helperAvailable:false,now:t0+60) == HeatAction.none)
        #expect(HeatHoldPolicy.step(snapshot:hot(33,at:t0+120),limit:held,settings:on,state:&st,helperAvailable:false,now:t0+120) == HeatAction.none)
        #expect(st.coolSince==nil)
        #expect(HeatHoldPolicy.step(snapshot:hot(31,at:t0+180),limit:held,settings:on,state:&st,helperAvailable:false,now:t0+180) == HeatAction.none)
        #expect(HeatHoldPolicy.step(snapshot:hot(31,at:t0+420),limit:held,settings:on,state:&st,helperAvailable:false,now:t0+420) == HeatAction.none)
        #expect(HeatHoldPolicy.step(snapshot:hot(31,at:t0+480),limit:held,settings:on,state:&st,helperAvailable:false,now:t0+480) == .restore(.setLimit(90)))
        #expect(st==HeatState())
    }
    @Test func externalChangeDuringHoldIsNeverOverwritten() {
        let t0=Date();var st=HeatState()
        _=HeatHoldPolicy.step(snapshot:hot(36,at:t0),limit:limit90,settings:on,state:&st,helperAvailable:false,now:t0)
        let changed=ChargeLimitState(supported:true,enabled:true,limit:95)
        #expect(HeatHoldPolicy.step(snapshot:hot(30,at:t0+600),limit:changed,settings:on,state:&st,helperAvailable:false,now:t0+600) == HeatAction.none)
        #expect(st==HeatState())
    }
    @Test func staleOrMissingTemperatureNeverHoldsOrResumes() {
        let t0=Date();var st=HeatState()
        #expect(HeatHoldPolicy.step(snapshot:hot(nil,at:t0),limit:limit90,settings:on,state:&st,helperAvailable:true,now:t0) == .sensorUnavailable)
        #expect(HeatHoldPolicy.step(snapshot:hot(40,at:t0-121),limit:limit90,settings:on,state:&st,helperAvailable:true,now:t0) == .sensorUnavailable)
        st.holdLimit=85;st.userLimit=90;st.coolSince=t0-1000
        let held=ChargeLimitState(supported:true,enabled:true,limit:85)
        #expect(HeatHoldPolicy.step(snapshot:hot(20,at:t0-500),limit:held,settings:on,state:&st,helperAvailable:true,now:t0) == .sensorUnavailable)
        #expect(st.holdLimit==85);#expect(st.coolSince==nil)
    }
    @Test func lowChargeOrMissingHelperOnlyWarns() {
        let t0=Date();var st=HeatState()
        #expect(HeatHoldPolicy.step(snapshot:hot(40,percent:45,at:t0),limit:limit90,settings:on,state:&st,helperAvailable:true,now:t0) == .cannotHold)
        #expect(HeatHoldPolicy.step(snapshot:hot(40,percent:70,at:t0),limit:limit90,settings:on,state:&st,helperAvailable:false,now:t0) == .cannotHold)
        #expect(st==HeatState())
        #expect(HeatHoldPolicy.step(snapshot:hot(40,percent:70,at:t0),limit:limit90,settings:on,state:&st,helperAvailable:true,now:t0) == .hold(70))
        #expect(st.holdLimit==70);#expect(st.userLimit==90)
    }
    @Test func unknownLimitOrDisabledFeatureNeverHolds() {
        let t0=Date();var st=HeatState()
        #expect(HeatHoldPolicy.step(snapshot:hot(40,at:t0),limit:ChargeLimitState(),settings:on,state:&st,helperAvailable:true,now:t0) == .cannotHold)
        #expect(HeatHoldPolicy.step(snapshot:hot(40,at:t0),limit:limit90,settings:HeatSettings(),state:&st,helperAvailable:true,now:t0) == HeatAction.none)
        var idle=hot(40,at:t0);idle.charging=false
        #expect(HeatHoldPolicy.step(snapshot:idle,limit:limit90,settings:on,state:&st,helperAvailable:true,now:t0) == HeatAction.none)
        #expect(st==HeatState())
    }
    @Test func disablingDuringHoldRestoresNoLimitWhenNoneExisted() {
        let t0=Date();var st=HeatState()
        let none=ChargeLimitState(supported:true,enabled:false,limit:nil)
        #expect(HeatHoldPolicy.step(snapshot:hot(40,at:t0),limit:none,settings:on,state:&st,helperAvailable:false,now:t0) == .hold(85))
        let held=ChargeLimitState(supported:true,enabled:true,limit:85)
        #expect(HeatHoldPolicy.step(snapshot:hot(40,at:t0+30),limit:held,settings:HeatSettings(),state:&st,helperAvailable:false,now:t0+30) == .restore(.clearLimit))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$SWIFT test --disable-xctest --filter ChargeControlTests 2>&1 | tail -5`
Expected: build FAILS with `cannot find 'ChargeCommand' in scope` (and similar for the other new types).

- [ ] **Step 3: Implement**

`Sources/BatteryCore/ChargeControl.swift`:

```swift
import Foundation
public enum ChargeCommand: Equatable, Sendable {
    case setLimit(Int), clearLimit, startTopUp, endTopUp
    public static let range=50...100
    /// macOS lets user processes set 80–100; lower limits need the root helper.
    public static let userFloor=80
    public var isValid:Bool { if case .setLimit(let p)=self { return Self.range.contains(p) };return true }
    public var requiresHelper:Bool { if case .setLimit(let p)=self { return p<Self.userFloor };return false }
}
public enum LimitOrigin: String, Codable, Sendable { case vibeBattery, external, none, unknown }
public struct ChargeLimitState: Codable, Equatable, Sendable {
    public var supported:Bool?;public var enabled:Bool?;public var limit:Int?
    public init(supported:Bool?=nil,enabled:Bool?=nil,limit:Int?=nil) { self.supported=supported;self.enabled=enabled;self.limit=limit }
    public func origin(lastWritten:Int?) -> LimitOrigin {
        guard supported==true,let enabled else { return .unknown }
        if !enabled { return .none }
        guard let limit else { return .unknown }
        return lastWritten==limit ? .vibeBattery:.external
    }
    /// Whether a read-back state confirms a command. nil: macOS gives no observable confirmation.
    public func matches(_ c:ChargeCommand) -> Bool? {
        switch c {
        case .setLimit(let p):return enabled==true && limit==p
        case .clearLimit:return enabled==false
        case .endTopUp:return enabled==true
        case .startTopUp:return nil
        }
    }
}
public struct HeatSettings: Codable, Equatable, Sendable {
    public var enabled=false;public var holdAt=35.0;public var resumeAt=32.0
    public init() {}
    public mutating func validate() {
        if !(30...45).contains(holdAt) { holdAt=35 }
        if !resumeAt.isFinite || resumeAt<25 || resumeAt>=holdAt { resumeAt=min(32,holdAt-1) }
    }
}
public struct HeatState: Codable, Equatable, Sendable {
    public var holdLimit:Int?;public var userLimit:Int?;public var coolSince:Date?
    public init() {}
}
public enum HeatAction: Equatable, Sendable { case none, hold(Int), restore(ChargeCommand), cannotHold, sensorUnavailable }
public enum HeatHoldPolicy {
    public static let stableResume:TimeInterval=300, staleAfter:TimeInterval=120, minimumHold=50
    public static func step(snapshot b:BatterySnapshot,limit:ChargeLimitState,settings:HeatSettings,state:inout HeatState,helperAvailable:Bool,now:Date=Date()) -> HeatAction {
        if let hold=state.holdLimit {
            // Someone changed the limit during the hold: their value wins.
            guard limit.enabled==true,limit.limit==hold else { state=HeatState();return .none }
            if !settings.enabled { return finish(&state) }
            guard let t=fresh(b,now) else { state.coolSince=nil;return .sensorUnavailable }
            guard t<=settings.resumeAt else { state.coolSince=nil;return .none }
            guard let since=state.coolSince else { state.coolSince=now;return .none }
            return now.timeIntervalSince(since)>=stableResume ? finish(&state):.none
        }
        guard settings.enabled else { return .none }
        guard let t=fresh(b,now) else { return .sensorUnavailable }
        guard t>=settings.holdAt,b.onAC,b.charging,let p=b.percent else { return .none }
        guard limit.supported==true,let enabled=limit.enabled,
              p>=minimumHold,p>=ChargeCommand.userFloor || helperAvailable else { return .cannotHold }
        state.holdLimit=p;state.userLimit=enabled ? limit.limit:nil;state.coolSince=nil
        return .hold(p)
    }
    private static func fresh(_ b:BatterySnapshot,_ now:Date) -> Double? {
        let age=now.timeIntervalSince(b.timestamp)
        return age >= -5 && age<=staleAfter ? b.temperature:nil
    }
    private static func finish(_ s:inout HeatState) -> HeatAction {
        let user=s.userLimit;s=HeatState()
        return .restore(user.map { .setLimit($0) } ?? .clearLimit)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `$SWIFT test --disable-xctest 2>&1 | tail -3`
Expected: `Test run with 27 tests in 5 suites passed` (17 existing + 10 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/BatteryCore/ChargeControl.swift Tests/BatteryCoreTests/ChargeControlTests.swift
git commit -m "feat: model charge commands and heat-hold hysteresis"
```

---

### Task 2: Other charge-controller detection

**Files:**
- Create: `Sources/BatteryCore/ChargeControllerDetector.swift`
- Create: `Sources/BatteryPlatform/ChargeControllerScan.swift`
- Test: `Tests/BatteryCoreTests/ChargeControllerDetectorTests.swift`

**Interfaces:**
- Produces:
  - `struct OtherChargeController: Equatable, Sendable { let name: String; let evidence: String }` with public `init(name:evidence:)`
  - `enum ChargeControllerDetector { static func detect(runningBundleIDs: [String], systemItems: [String]) -> [OtherChargeController] }`
  - `enum ChargeControllerScan { static func current() -> [OtherChargeController] }` (scans running apps and `/Library/LaunchDaemons`, `/Library/PrivilegedHelperTools`)

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `$SWIFT test --disable-xctest --filter ChargeControllerDetectorTests 2>&1 | tail -5`
Expected: build FAILS with `cannot find 'ChargeControllerDetector' in scope`.

- [ ] **Step 3: Implement**

`Sources/BatteryCore/ChargeControllerDetector.swift`:

```swift
import Foundation
public struct OtherChargeController: Equatable, Sendable {
    public let name:String;public let evidence:String
    public init(name:String,evidence:String) { self.name=name;self.evidence=evidence }
}
public enum ChargeControllerDetector {
    // AlDente's identifiers were observed on the target Mac; batt's daemon label is from its public installer.
    private static let rules:[(name:String,prefix:String)]=[("AlDente","com.apphousekitchen.aldente"),("batt","cc.chlc.batt")]
    public static func detect(runningBundleIDs:[String],systemItems:[String]) -> [OtherChargeController] {
        rules.compactMap { r -> OtherChargeController? in
            if let id=runningBundleIDs.first(where:{ $0.lowercased().hasPrefix(r.prefix) }) { return .init(name:r.name,evidence:"실행 중: \(id)") }
            if let item=systemItems.first(where:{ ($0 as NSString).lastPathComponent.lowercased().hasPrefix(r.prefix) }) { return .init(name:r.name,evidence:"설치됨: \(item)") }
            return nil
        }
    }
}
```

`Sources/BatteryPlatform/ChargeControllerScan.swift`:

```swift
import Foundation
import AppKit
import BatteryCore
public enum ChargeControllerScan {
    public static let directories=["/Library/LaunchDaemons","/Library/PrivilegedHelperTools"]
    public static func current() -> [OtherChargeController] {
        let ids=NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let items=directories.flatMap { d in ((try? FileManager.default.contentsOfDirectory(atPath:d)) ?? []).map { "\(d)/\($0)" } }
        return ChargeControllerDetector.detect(runningBundleIDs:ids,systemItems:items)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `$SWIFT test --disable-xctest 2>&1 | tail -3`
Expected: `Test run with 31 tests in 6 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/BatteryCore/ChargeControllerDetector.swift Sources/BatteryPlatform/ChargeControllerScan.swift Tests/BatteryCoreTests/ChargeControllerDetectorTests.swift
git commit -m "feat: detect other charge managers before any write"
```

---

### Task 3: PowerUI bridge and `vbctl charge status`

**Files:**
- Create: `Sources/MacBridge/PowerUI.m`
- Modify: `Sources/MacBridge/include/MacBridge.h` (append declarations)
- Modify: `Package.swift` (MacBridge links Foundation; test target depends on MacBridge)
- Create: `Sources/BatteryPlatform/ChargeLimitClient.swift`
- Modify: `Sources/VibeCLI/Main.swift` (add `charge status` case and usage line)
- Test: `Tests/BatteryCoreTests/PowerUIBridgeTests.swift`

**Interfaces:**
- Consumes: `ChargeCommand`, `ChargeLimitState` (Task 1); `ChargeControllerScan.current()` (Task 2).
- Produces:
  - C: `typedef struct { int32_t supported, enabled, limit; } VBChargeLimit;` (-1 = unknown); `int vb_mcl_read(VBChargeLimit *)`, `int vb_mcl_set_limit(int32_t)`, `int vb_mcl_top_up(void)`, `int vb_mcl_enable(void)`, `int vb_mcl_disable(void)`; return 0 ok, -1 unavailable, -2 rejected, -3 out of range.
  - Swift: `protocol ChargeLimitBackend { func read() -> ChargeLimitState; func perform(_ c: ChargeCommand) -> Bool }`, `struct PowerUIChargeBackend: ChargeLimitBackend` with `public init()`.
  - CLI: `vbctl charge status [--json]`.

- [ ] **Step 1: Write the failing test**

`Tests/BatteryCoreTests/PowerUIBridgeTests.swift`:

```swift
import Testing
import MacBridge
struct PowerUIBridgeTests {
    // Never pass 80...100 here: that would change this Mac's real charge limit.
    @Test func outOfRangeLimitsAreRejectedBeforeCallingMacOS() {
        #expect(vb_mcl_set_limit(79) == -3);#expect(vb_mcl_set_limit(101) == -3);#expect(vb_mcl_set_limit(-1) == -3)
    }
}
```

Modify `Package.swift` test target: `.testTarget(name: "BatteryCoreTests", dependencies: ["BatteryCore", "BatteryPlatform", "MacBridge"])`.

- [ ] **Step 2: Run to verify failure**

Run: `$SWIFT test --disable-xctest --filter PowerUIBridgeTests 2>&1 | tail -5`
Expected: build FAILS with `cannot find 'vb_mcl_set_limit' in scope`.

- [ ] **Step 3: Implement the bridge**

Append to `Sources/MacBridge/include/MacBridge.h`:

```c
typedef struct { int32_t supported, enabled, limit; } VBChargeLimit;
// 0 ok, -1 PowerUI unavailable, -2 rejected by macOS, -3 out of range.
int vb_mcl_read(VBChargeLimit *out);
int vb_mcl_set_limit(int32_t percent);
int vb_mcl_top_up(void);
int vb_mcl_enable(void);
int vb_mcl_disable(void);
```

`Sources/MacBridge/PowerUI.m`:

```objc
#import <Foundation/Foundation.h>
#include "MacBridge.h"
// Private client behind System Settings' Charge Limit. Selectors were confirmed on
// macOS 27.0.1 (26A434); each call re-checks that the selector still exists.
@protocol VBSmartChargeClient
- (instancetype)initWithClientName:(NSString *)name;
- (BOOL)isMCLSupported;
- (unsigned long long)isMCLCurrentlyEnabled:(NSError **)error;
- (unsigned char)getMCLLimitWithError:(NSError **)error;
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)error;
- (BOOL)temporarilyDisableMCL:(NSError **)error;
- (BOOL)enableMCL:(NSError **)error;
- (BOOL)disableMCL:(NSError **)error;
@end
static id<VBSmartChargeClient> vb_client(SEL selector) {
    static id<VBSmartChargeClient> client=nil; static dispatch_once_t once;
    dispatch_once(&once,^{
        if (![[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/PowerUI.framework"] load]) return;
        Class type=NSClassFromString(@"PowerUISmartChargeClient");
        if (type && [type instancesRespondToSelector:@selector(initWithClientName:)])
            client=[(id<VBSmartChargeClient>)[type alloc] initWithClientName:@"io.github.y-minion.vibebattery"];
    });
    return [(id)client respondsToSelector:selector] ? client : nil;
}
int vb_mcl_read(VBChargeLimit *out) {
    out->supported=out->enabled=out->limit=-1;
    id<VBSmartChargeClient> c=vb_client(@selector(isMCLSupported));
    if (!c) return -1;
    out->supported=[c isMCLSupported]?1:0;
    if (!out->supported) return 0;
    NSError *e=nil;
    if ([(id)c respondsToSelector:@selector(isMCLCurrentlyEnabled:)]) { unsigned long long v=[c isMCLCurrentlyEnabled:&e]; if (!e) out->enabled=v?1:0; }
    e=nil;
    if ([(id)c respondsToSelector:@selector(getMCLLimitWithError:)]) { unsigned char v=[c getMCLLimitWithError:&e]; if (!e && v>0 && v<=100) out->limit=v; }
    return 0;
}
int vb_mcl_set_limit(int32_t percent) {
    // PowerUI crashes below 80; lower limits go through the root helper.
    if (percent<80 || percent>100) return -3;
    id<VBSmartChargeClient> c=vb_client(@selector(setMCLLimit:error:));
    if (!c) return -1;
    NSError *e=nil; return [c setMCLLimit:(unsigned char)percent error:&e] && !e ? 0 : -2;
}
int vb_mcl_top_up(void) {
    id<VBSmartChargeClient> c=vb_client(@selector(temporarilyDisableMCL:)); if (!c) return -1;
    NSError *e=nil; return [c temporarilyDisableMCL:&e] && !e ? 0 : -2;
}
int vb_mcl_enable(void) {
    id<VBSmartChargeClient> c=vb_client(@selector(enableMCL:)); if (!c) return -1;
    NSError *e=nil; return [c enableMCL:&e] && !e ? 0 : -2;
}
int vb_mcl_disable(void) {
    id<VBSmartChargeClient> c=vb_client(@selector(disableMCL:)); if (!c) return -1;
    NSError *e=nil; return [c disableMCL:&e] && !e ? 0 : -2;
}
```

In `Package.swift`, MacBridge becomes: `.target(name: "MacBridge", linkerSettings: [.linkedLibrary("proc"), .linkedFramework("Foundation")])`.

- [ ] **Step 4: Run to verify pass**

Run: `$SWIFT test --disable-xctest 2>&1 | tail -3`
Expected: `Test run with 32 tests in 7 suites passed`. If the build fails because the local toolchain cannot compile Objective-C in a SwiftPM target, use superpowers:systematic-debugging; do not move the range guard out of C.

- [ ] **Step 5: Implement the Swift backend and CLI**

`Sources/BatteryPlatform/ChargeLimitClient.swift`:

```swift
import Foundation
import BatteryCore
import MacBridge
public protocol ChargeLimitBackend {
    func read() -> ChargeLimitState
    func perform(_ c:ChargeCommand) -> Bool
}
public struct PowerUIChargeBackend: ChargeLimitBackend {
    public init() {}
    public func read() -> ChargeLimitState {
        var raw=VBChargeLimit(supported:-1,enabled:-1,limit:-1);_=vb_mcl_read(&raw)
        func flag(_ v:Int32) -> Bool? { v<0 ? nil:v==1 }
        return ChargeLimitState(supported:flag(raw.supported),enabled:flag(raw.enabled),limit:raw.limit<0 ? nil:Int(raw.limit))
    }
    public func perform(_ c:ChargeCommand) -> Bool {
        switch c {
        case .setLimit(let p):return vb_mcl_set_limit(Int32(p))==0
        case .clearLimit:return vb_mcl_disable()==0
        case .startTopUp:return vb_mcl_top_up()==0
        case .endTopUp:return vb_mcl_enable()==0
        }
    }
}
public enum ChargeText {
    public static func limit(_ s:ChargeLimitState) -> String {
        if s.supported==false { return "이 Mac에서 지원 안 됨" }
        if s.enabled==false { return "상한 꺼짐 (100%까지 충전)" }
        return s.limit.map { "현재 상한 \($0)%" } ?? "상한 알 수 없음"
    }
}
```

In `Sources/VibeCLI/Main.swift`, add before `default:`:

```swift
            case "charge":
                guard args.count>=2,args[1]=="status" else { throw OptionError.invalid("사용법: vbctl charge status [--json]") }
                let s=PowerUIChargeBackend().read()
                if args.contains("--json") { print(String(data:try JSONEncoder().encode(s),encoding:.utf8)!) }
                else {
                    print("충전: \(ChargeText.limit(s))")
                    for o in ChargeControllerScan.current() { print("다른 충전 관리: \(o.name) (\(o.evidence))") }
                }
```

and add the usage line `  vbctl charge status [--json]` after `vbctl status [--json]`.

- [ ] **Step 6: Verify read-only on this Mac**

Run: `$SWIFT build 2>&1 | tail -1 && .build/debug/vbctl charge status && .build/debug/vbctl charge status --json`
Expected (values as of 2026-10-20; the limit may differ if AlDente changed it; JSON key order may vary):
```
충전: 현재 상한 79%
다른 충전 관리: AlDente (실행 중: com.apphousekitchen.aldente-pro)
{"supported":true,"enabled":true,"limit":79}
```
Then run `pmset -g battlimit | grep chargeSocLimitSoc` and confirm the same number. A mismatch is a bug in `vb_mcl_read`.

- [ ] **Step 7: Run all tests and commit**

Run: `$SWIFT test --disable-xctest 2>&1 | tail -1`
Expected: `Test run with 32 tests in 7 suites passed`.

```bash
git add Package.swift Sources/MacBridge Sources/BatteryPlatform/ChargeLimitClient.swift Sources/VibeCLI/Main.swift Tests/BatteryCoreTests/PowerUIBridgeTests.swift
git commit -m "feat: read the macOS charge limit through PowerUI"
```

---

### Task 4: Charge controller with conflict gate, routing, and read-back

**Files:**
- Create: `Sources/BatteryPlatform/ChargeController.swift`
- Test: `Tests/BatteryCoreTests/ChargeControllerTests.swift`

**Interfaces:**
- Consumes: Task 1 types; `OtherChargeController` (Task 2); `ChargeLimitBackend` (Task 3).
- Produces:
  - `protocol ChargeHelperClient { var isInstalled: Bool { get }; func setLimit(_ percent: Int) -> String? }` (nil = success, otherwise a Korean error message)
  - `enum ChargeError: Error, Equatable, LocalizedError { case invalid, conflict([String]), helperRequired, unavailable, rejected(String), notApplied }`
  - `struct ChargeRecord: Codable, Equatable { var lastWritten: Int?; var heat: HeatState; var heatPaused: Bool; var topUpRequested: Date? }`
  - `final class ChargeController` — `init(backend:helper:detect:url:)`, `record`, `helperInstalled`, `state()`, `apply(_:byUser:) -> Result<ChargeLimitState, ChargeError>`, `heatStep(snapshot:settings:now:) -> (action: HeatAction, result: Result<ChargeLimitState, ChargeError>?)`, `resumeHeat()`

- [ ] **Step 1: Write the failing tests**

`Tests/BatteryCoreTests/ChargeControllerTests.swift`:

```swift
import Testing
import Foundation
import BatteryCore
@testable import BatteryPlatform
final class FakeBackend: ChargeLimitBackend {
    var state=ChargeLimitState(supported:true,enabled:true,limit:79);var accept=true;var ignore=false;var calls:[ChargeCommand]=[]
    func read() -> ChargeLimitState { state }
    func perform(_ c:ChargeCommand) -> Bool {
        calls.append(c);guard accept else { return false };if ignore { return true }
        switch c {
        case .setLimit(let p):state.enabled=true;state.limit=p
        case .clearLimit:state.enabled=false
        case .endTopUp:state.enabled=true
        case .startTopUp:break
        }
        return true
    }
}
final class FakeHelper: ChargeHelperClient {
    var isInstalled=true;let backend:FakeBackend;var calls:[Int]=[]
    init(_ b:FakeBackend) { backend=b }
    func setLimit(_ p:Int) -> String? { calls.append(p);backend.state.enabled=true;backend.state.limit=p;return nil }
}
struct ChargeControllerTests {
    func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("charge.json") }
    func make(_ b:FakeBackend,helper:FakeHelper?=nil,others:[OtherChargeController]=[],at u:URL?=nil) -> ChargeController {
        ChargeController(backend:b,helper:helper,detect:{ others },url:u ?? url())
    }
    func hot(_ t:Double,at now:Date) -> BatterySnapshot {
        var b=BatterySnapshot();b.timestamp=now;b.temperature=t;b.percent=85;b.onAC=true;b.charging=true;return b
    }
    var heatOn:HeatSettings { var s=HeatSettings();s.enabled=true;return s }
    @Test func conflictingControllerBlocksEveryWrite() {
        let b=FakeBackend();let c=make(b,others:[.init(name:"AlDente",evidence:"실행 중")])
        #expect(c.apply(.setLimit(80)) == .failure(.conflict(["AlDente"])))
        #expect(c.apply(.startTopUp) == .failure(.conflict(["AlDente"])))
        #expect(b.calls.isEmpty)
    }
    @Test func invalidAndUnsupportedAreRejectedWithoutWrites() {
        let b=FakeBackend();let c=make(b)
        #expect(c.apply(.setLimit(40)) == .failure(.invalid))
        b.state=ChargeLimitState(supported:false)
        #expect(c.apply(.setLimit(80)) == .failure(.unavailable))
        #expect(b.calls.isEmpty)
    }
    @Test func lowLimitsRouteToHelperAndRequireIt() {
        let b=FakeBackend();let h=FakeHelper(b)
        #expect(make(b).apply(.setLimit(70)) == .failure(.helperRequired))
        h.isInstalled=false;#expect(make(b,helper:h).apply(.setLimit(70)) == .failure(.helperRequired))
        h.isInstalled=true;let c=make(b,helper:h)
        #expect(c.apply(.setLimit(70)) == .success(ChargeLimitState(supported:true,enabled:true,limit:70)))
        #expect(h.calls==[70]);#expect(b.calls.isEmpty);#expect(c.record.lastWritten==70)
    }
    @Test func readbackMismatchIsReportedOnceWithoutRecordingOwnership() {
        let b=FakeBackend();b.ignore=true;let c=make(b)
        #expect(c.apply(.setLimit(85)) == .failure(.notApplied))
        #expect(b.calls==[.setLimit(85)]);#expect(c.record.lastWritten==nil)
    }
    @Test func rejectedWriteIsReported() {
        let b=FakeBackend();b.accept=false
        #expect(make(b).apply(.clearLimit) == .failure(.rejected("macOS가 요청을 거부했습니다.")))
    }
    @Test func recordSurvivesRestart() {
        let b=FakeBackend();let u=url()
        _=make(b,at:u).apply(.setLimit(85));_=make(b,at:u).apply(.startTopUp)
        let again=make(b,at:u);#expect(again.record.lastWritten==85);#expect(again.record.topUpRequested != nil)
    }
    @Test func heatHoldSurvivesRestartAndRestoresUserLimit() {
        let b=FakeBackend();b.state.limit=90;let u=url();let t0=Date()
        let first=make(b,at:u).heatStep(snapshot:hot(40,at:t0),settings:heatOn,now:t0)
        #expect(first.action == .hold(85));#expect(b.state.limit==85)
        let restarted=make(b,at:u)
        #expect(restarted.heatStep(snapshot:hot(30,at:t0+60),settings:heatOn,now:t0+60).action == HeatAction.none)
        let done=restarted.heatStep(snapshot:hot(30,at:t0+400),settings:heatOn,now:t0+400)
        #expect(done.action == .restore(.setLimit(90)));#expect(b.state.limit==90);#expect(restarted.record.lastWritten==90)
    }
    @Test func failedHeatHoldPausesInsteadOfRetrying() {
        let b=FakeBackend();b.state.limit=90;b.ignore=true;let c=make(b);let t0=Date()
        #expect(c.heatStep(snapshot:hot(40,at:t0),settings:heatOn,now:t0).result == .failure(.notApplied))
        #expect(c.record.heatPaused);#expect(c.record.heat==HeatState())
        #expect(c.heatStep(snapshot:hot(40,at:t0+30),settings:heatOn,now:t0+30).action == HeatAction.none)
        #expect(b.calls.count==1)
        c.resumeHeat();#expect(!c.record.heatPaused)
    }
    @Test func userApplyCancelsHoldAndHeatSkipsDuringConflict() {
        let b=FakeBackend();b.state.limit=90;let t0=Date();let c=make(b)
        _=c.heatStep(snapshot:hot(40,at:t0),settings:heatOn,now:t0)
        _=c.apply(.setLimit(95));#expect(c.record.heat==HeatState())
        let blocked=make(b,others:[.init(name:"AlDente",evidence:"")])
        #expect(blocked.heatStep(snapshot:hot(40,at:t0),settings:heatOn,now:t0).action == HeatAction.none)
        #expect(b.state.limit==95)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `$SWIFT test --disable-xctest --filter ChargeControllerTests 2>&1 | tail -5`
Expected: build FAILS with `cannot find type 'ChargeHelperClient' in scope`.

- [ ] **Step 3: Implement**

`Sources/BatteryPlatform/ChargeController.swift`:

```swift
import Foundation
import BatteryCore
public protocol ChargeHelperClient {
    var isInstalled:Bool { get }
    /// nil on success, otherwise a user-facing reason.
    func setLimit(_ percent:Int) -> String?
}
public enum ChargeError: Error, Equatable, LocalizedError {
    case invalid, conflict([String]), helperRequired, unavailable, rejected(String), notApplied
    public var errorDescription:String? {
        switch self {
        case .invalid:return "충전 상한은 50~100% 사이에서 고를 수 있습니다."
        case .conflict(let names):return "\(names.joined(separator:", "))이(가) 충전을 관리하고 있습니다. 해당 앱을 종료하거나 삭제하면 제어할 수 있습니다."
        case .helperRequired:return "80% 미만 상한에는 VibeBattery 헬퍼 설치가 필요합니다."
        case .unavailable:return "이 macOS에서 충전 상한 제어를 확인하지 못했습니다."
        case .rejected(let m):return m
        case .notApplied:return "적용 실패: 다시 읽은 값이 요청과 다릅니다. 자동으로 재시도하지 않습니다."
        }
    }
}
public struct ChargeRecord: Codable, Equatable {
    public var lastWritten:Int?;public var heat=HeatState();public var heatPaused=false;public var topUpRequested:Date?
    public init() {}
}
public final class ChargeController {
    private let backend:ChargeLimitBackend;private let helper:ChargeHelperClient?
    private let detect:()->[OtherChargeController];private let url:URL
    public private(set) var record:ChargeRecord
    public init(backend:ChargeLimitBackend,helper:ChargeHelperClient?,detect:@escaping ()->[OtherChargeController],url:URL) {
        self.backend=backend;self.helper=helper;self.detect=detect;self.url=url
        record=(try? JSONDecoder().decode(ChargeRecord.self,from:Data(contentsOf:url))) ?? ChargeRecord()
    }
    public var helperInstalled:Bool { helper?.isInstalled==true }
    public func state() -> ChargeLimitState { backend.read() }
    @discardableResult public func apply(_ c:ChargeCommand,byUser:Bool=true) -> Result<ChargeLimitState,ChargeError> {
        guard c.isValid else { return .failure(.invalid) }
        let others=detect();guard others.isEmpty else { return .failure(.conflict(others.map(\.name))) }
        guard backend.read().supported==true else { return .failure(.unavailable) }
        if byUser { record.heat=HeatState();record.heatPaused=false }
        defer { save() }
        if case .setLimit(let p)=c,c.requiresHelper {
            guard let helper,helper.isInstalled else { return .failure(.helperRequired) }
            if let m=helper.setLimit(p) { return .failure(.rejected(m)) }
        } else if !backend.perform(c) { return .failure(.rejected("macOS가 요청을 거부했습니다.")) }
        let s=backend.read()
        guard s.matches(c) != false else { return .failure(.notApplied) }
        switch c {
        case .setLimit(let p):record.lastWritten=p
        case .clearLimit:record.lastWritten=nil
        case .startTopUp:record.topUpRequested=Date()
        case .endTopUp:record.topUpRequested=nil
        }
        return .success(s)
    }
    public func heatStep(snapshot:BatterySnapshot,settings:HeatSettings,now:Date=Date()) -> (action:HeatAction,result:Result<ChargeLimitState,ChargeError>?) {
        guard !record.heatPaused,detect().isEmpty else { return (.none,nil) }
        var h=record.heat
        let a=HeatHoldPolicy.step(snapshot:snapshot,limit:backend.read(),settings:settings,state:&h,helperAvailable:helperInstalled,now:now)
        record.heat=h;save()
        let command:ChargeCommand
        switch a {
        case .hold(let p):command = .setLimit(p)
        case .restore(let c):command=c
        default:return (a,nil)
        }
        let r=apply(command,byUser:false)
        // A failed automatic write must not repeat every refresh.
        if case .failure=r { record.heat=HeatState();record.heatPaused=true;save() }
        return (a,r)
    }
    public func resumeHeat() { record.heatPaused=false;save() }
    private func save() {
        try? FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try? JSONEncoder().encode(record).write(to:url,options:[.atomic])
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `$SWIFT test --disable-xctest 2>&1 | tail -3`
Expected: `Test run with 41 tests in 8 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/BatteryPlatform/ChargeController.swift Tests/BatteryCoreTests/ChargeControllerTests.swift
git commit -m "feat: gate, route and verify charge limit writes"
```

---

### Task 5: Minimal root helper, XPC client, and install scripts

**Files:**
- Create: `Sources/BatteryCore/HelperPolicy.swift`
- Create: `Sources/BatteryPlatform/ChargeHelperXPC.swift`
- Create: `Sources/VBChargeHelper/main.swift`
- Modify: `Sources/MacBridge/include/MacBridge.h`, `Sources/MacBridge/MacBridge.c` (add `vb_pid_path`, `vb_notify`)
- Modify: `Package.swift` (new product + executable target)
- Create: `scripts/install-helper.sh`, `scripts/uninstall-helper.sh`
- Test: `Tests/BatteryCoreTests/HelperPolicyTests.swift`

**Interfaces:**
- Consumes: `ChargeCommand.range` (Task 1), `ChargeHelperClient` (Task 4).
- Produces:
  - `enum HelperPolicy { static let label, appIdentifier, clientRequirement, helperRequirement, appPrefix, daemonPlist; static func allows(clientUID: UInt32, consoleUID: UInt32?, clientPath: String?) -> Bool }`
  - `enum TopoffDomain { static let name, limitKey, featureKey, notification; static func writes(limit: Int, existingFeature: Any?) -> [String: Any]? }`
  - `@objc protocol ChargeHelperProtocol { func setLimit(_ percent: Int, reply: @escaping (String?) -> Void); func readState(reply: @escaping ([String: String]) -> Void) }`
  - `final class XPCChargeHelper: ChargeHelperClient` with `init()`, `readState() -> [String: String]?`
  - C: `int vb_pid_path(int32_t pid, char *buffer, int size)` (0 ok), `int vb_notify(const char *name)`
  - Executable `VBChargeHelper`; launchd label and Mach service `io.github.y-minion.vibebattery.helper`.

**Ruling recorded here (narrower than spec 4.4):** the helper implements only `setLimit` and `readState`. Clear and one-time full charge go through PowerUI as the user (Task 3). If Task 8 shows they fail after a root-set limit, that is a new finding for a follow-up, not a reason to widen the helper now. The spec's SMAppService check is replaced by the install script because SMAppService daemon registration needs the user at the Mac to approve and has no advantage before Developer ID signing (spec section 8, item 4).

- [ ] **Step 1: Write the failing tests**

`Tests/BatteryCoreTests/HelperPolicyTests.swift`:

```swift
import Testing
import Foundation
import BatteryCore
struct HelperPolicyTests {
    let app="/Applications/VibeBattery.app/Contents/MacOS/VibeBattery"
    @Test func onlyConsoleUserRunningInstalledAppIsAllowed() {
        #expect(HelperPolicy.allows(clientUID:501,consoleUID:501,clientPath:app))
        #expect(!HelperPolicy.allows(clientUID:502,consoleUID:501,clientPath:app))
        #expect(!HelperPolicy.allows(clientUID:0,consoleUID:0,clientPath:app))
        #expect(!HelperPolicy.allows(clientUID:501,consoleUID:nil,clientPath:app))
        #expect(!HelperPolicy.allows(clientUID:501,consoleUID:501,clientPath:nil))
        #expect(!HelperPolicy.allows(clientUID:501,consoleUID:501,clientPath:"/tmp/VibeBattery.app/Contents/MacOS/VibeBattery"))
        #expect(!HelperPolicy.allows(clientUID:501,consoleUID:501,clientPath:"/Applications/VibeBattery.app/../Evil.app/x"))
        #expect(!HelperPolicy.allows(clientUID:501,consoleUID:501,clientPath:"/Applications/VibeBattery.appx/y"))
    }
    @Test func domainWritesAreBoundedAndKeepExistingFeatureState() {
        let fresh=TopoffDomain.writes(limit:79,existingFeature:nil)
        #expect((fresh?[TopoffDomain.limitKey] as? NSNumber)?.intValue==79)
        #expect((fresh?[TopoffDomain.featureKey] as? NSNumber)?.intValue==1)
        let kept=TopoffDomain.writes(limit:60,existingFeature:NSNumber(value:2))
        #expect(kept?.keys.sorted()==[TopoffDomain.limitKey])
        #expect(TopoffDomain.writes(limit:49,existingFeature:nil)==nil)
        #expect(TopoffDomain.writes(limit:101,existingFeature:nil)==nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `$SWIFT test --disable-xctest --filter HelperPolicyTests 2>&1 | tail -5`
Expected: build FAILS with `cannot find 'HelperPolicy' in scope`.

- [ ] **Step 3: Implement the pure policy**

`Sources/BatteryCore/HelperPolicy.swift`:

```swift
import Foundation
public enum HelperPolicy {
    public static let label="io.github.y-minion.vibebattery.helper"
    public static let appIdentifier="io.github.y-minion.vibebattery"
    // Ad-hoc builds have no team ID, so the requirement pins only the identifier.
    // Developer ID signing must add the team (spec section 8).
    public static let clientRequirement="identifier \"io.github.y-minion.vibebattery\""
    public static let helperRequirement="identifier \"io.github.y-minion.vibebattery.helper\""
    public static let appPrefix="/Applications/VibeBattery.app/"
    public static let daemonPlist="/Library/LaunchDaemons/io.github.y-minion.vibebattery.helper.plist"
    public static func allows(clientUID:UInt32,consoleUID:UInt32?,clientPath:String?) -> Bool {
        guard let consoleUID,consoleUID != 0,clientUID==consoleUID,let clientPath else { return false }
        return (clientPath as NSString).standardizingPath.hasPrefix(appPrefix)
    }
}
public enum TopoffDomain {
    public static let name="com.apple.smartcharging.topoffprotection"
    public static let limitKey="mclLimitValue",featureKey="MCLFeatureState"
    public static let notification="com.apple.smartcharging.defaultschanged"
    /// Keys to write for a limit. An existing feature state is left alone so an
    /// encoding we have not observed is never replaced.
    public static func writes(limit:Int,existingFeature:Any?) -> [String:Any]? {
        guard ChargeCommand.range.contains(limit) else { return nil }
        var w:[String:Any]=[limitKey:NSNumber(value:limit)]
        if existingFeature==nil { w[featureKey]=NSNumber(value:1) }
        return w
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `$SWIFT test --disable-xctest 2>&1 | tail -3`
Expected: `Test run with 43 tests in 9 suites passed`.

- [ ] **Step 5: Implement the C helpers, XPC protocol/client, and helper executable**

Append to `Sources/MacBridge/include/MacBridge.h`:

```c
int vb_pid_path(int32_t pid, char *buffer, int size);
int vb_notify(const char *name);
```

Append to `Sources/MacBridge/MacBridge.c`:

```c
#include <notify.h>
int vb_pid_path(int32_t pid,char *buffer,int size) { return proc_pidpath(pid,buffer,(uint32_t)size)>0?0:-1; }
int vb_notify(const char *name) { return (int)notify_post(name); }
```

`Sources/BatteryPlatform/ChargeHelperXPC.swift`:

```swift
import Foundation
import BatteryCore
@objc public protocol ChargeHelperProtocol {
    func setLimit(_ percent:Int,reply:@escaping (String?)->Void)
    func readState(reply:@escaping ([String:String])->Void)
}
public final class XPCChargeHelper: ChargeHelperClient {
    public init() {}
    public var isInstalled:Bool { FileManager.default.fileExists(atPath:HelperPolicy.daemonPlist) }
    private func connect() -> NSXPCConnection {
        let c=NSXPCConnection(machServiceName:HelperPolicy.label,options:.privileged)
        c.remoteObjectInterface=NSXPCInterface(with:ChargeHelperProtocol.self)
        c.setCodeSigningRequirement(HelperPolicy.helperRequirement)
        c.resume();return c
    }
    public func setLimit(_ percent:Int) -> String? {
        let c=connect();defer { c.invalidate() }
        var message:String?="헬퍼가 응답하지 않습니다."
        let proxy=c.synchronousRemoteObjectProxyWithErrorHandler { message="헬퍼 연결 실패: \($0.localizedDescription)" } as? ChargeHelperProtocol
        proxy?.setLimit(percent) { message=$0 }
        return message
    }
    public func readState() -> [String:String]? {
        let c=connect();defer { c.invalidate() }
        var state:[String:String]?
        let proxy=c.synchronousRemoteObjectProxyWithErrorHandler { _ in state=nil } as? ChargeHelperProtocol
        proxy?.readState { state=$0 }
        return state
    }
}
```

`Sources/VBChargeHelper/main.swift`:

```swift
import Foundation
import SystemConfiguration
import BatteryCore
import BatteryPlatform
import MacBridge
// Root daemon. Accepts only a bounded limit write and a state read from the
// console user's /Applications/VibeBattery.app; no generic defaults or commands.
final class Service:NSObject,ChargeHelperProtocol {
    let domain=TopoffDomain.name as CFString
    func value(_ key:String) -> CFPropertyList? { CFPreferencesCopyValue(key as CFString,domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost) }
    func setLimit(_ percent:Int,reply:@escaping (String?)->Void) {
        guard let writes=TopoffDomain.writes(limit:percent,existingFeature:value(TopoffDomain.featureKey)) else { return reply("허용 범위를 벗어난 상한입니다.") }
        for (key,v) in writes { CFPreferencesSetValue(key as CFString,v as CFPropertyList,domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost) }
        guard CFPreferencesSynchronize(domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost) else { return reply("설정을 저장하지 못했습니다.") }
        _=vb_notify(TopoffDomain.notification)
        reply(nil)
    }
    func readState(reply:@escaping ([String:String])->Void) {
        var r:[String:String]=[:]
        for key in [TopoffDomain.limitKey,TopoffDomain.featureKey] { r[key]=value(key).map { "\($0)" } ?? "없음" }
        reply(r)
    }
}
final class Gate:NSObject,NSXPCListenerDelegate {
    func listener(_ listener:NSXPCListener,shouldAcceptNewConnection c:NSXPCConnection) -> Bool {
        var console:uid_t=0
        let user=SCDynamicStoreCopyConsoleUser(nil,&console,nil)
        var buffer=[CChar](repeating:0,count:4096)
        let path=vb_pid_path(c.processIdentifier,&buffer,Int32(buffer.count))==0 ? String(cString:buffer):nil
        guard HelperPolicy.allows(clientUID:c.effectiveUserIdentifier,consoleUID:user==nil ? nil:console,clientPath:path) else { return false }
        // The signature check is enforced by XPC on every message, so a PID swap after the path check fails.
        c.setCodeSigningRequirement(HelperPolicy.clientRequirement)
        c.exportedInterface=NSXPCInterface(with:ChargeHelperProtocol.self)
        c.exportedObject=Service()
        c.resume();return true
    }
}
let gate=Gate()
let listener=NSXPCListener(machServiceName:HelperPolicy.label)
listener.delegate=gate;listener.resume()
RunLoop.main.run()
```

`Package.swift` additions: product `.executable(name: "VBChargeHelper", targets: ["VBChargeHelper"])` and target `.executableTarget(name: "VBChargeHelper", dependencies: ["BatteryCore", "BatteryPlatform", "MacBridge"], linkerSettings: [.linkedFramework("SystemConfiguration")])`.

`readState()` is for diagnostics only; no CLI subcommand calls it, because `vbctl` is signed with a different identifier and the helper's signature requirement would reject it. Task 8 diagnoses the domain with `sudo defaults read` instead.

- [ ] **Step 6: Write install/uninstall scripts**

`scripts/install-helper.sh`:

```sh
#!/bin/sh
# Installs VibeBattery's charge-limit helper as a root LaunchDaemon.
# Usage: sudo /Applications/VibeBattery.app/Contents/Resources/install-helper.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "관리자 권한이 필요합니다: sudo $0" >&2; exit 1; }
LABEL=io.github.y-minion.vibebattery.helper
APP=${1:-/Applications/VibeBattery.app}
SRC="$APP/Contents/MacOS/VBChargeHelper"
DEST=/Library/PrivilegedHelperTools/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist
[ "$APP" = /Applications/VibeBattery.app ] || echo "주의: 헬퍼는 /Applications/VibeBattery.app의 요청만 받습니다." >&2
codesign --verify --strict "$APP"
codesign -dv "$SRC" 2>&1 | grep -q "^Identifier=$LABEL\$" || { echo "헬퍼 서명 식별자가 다릅니다." >&2; exit 1; }
launchctl bootout "system/$LABEL" 2>/dev/null || true
install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
install -o root -g wheel -m 755 "$SRC" "$DEST"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array><string>$DEST</string></array>
<key>MachServices</key><dict><key>$LABEL</key><true/></dict>
</dict></plist>
EOF
chown root:wheel "$PLIST";chmod 644 "$PLIST"
launchctl bootstrap system "$PLIST"
echo "설치했습니다: $LABEL"
```

`scripts/uninstall-helper.sh`:

```sh
#!/bin/sh
# Removes the helper. The current charge limit is left as it is.
set -eu
[ "$(id -u)" = 0 ] || { echo "관리자 권한이 필요합니다: sudo $0" >&2; exit 1; }
LABEL=io.github.y-minion.vibebattery.helper
launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/$LABEL.plist" "/Library/PrivilegedHelperTools/$LABEL"
echo "헬퍼를 제거했습니다. 현재 충전 상한은 그대로 유지됩니다. 바꾸려면 macOS 배터리 설정을 사용하세요."
```

`chmod +x scripts/install-helper.sh scripts/uninstall-helper.sh`.

- [ ] **Step 7: Verify build and scripts without root**

Run: `$SWIFT build 2>&1 | tail -1; sh -n scripts/install-helper.sh && sh -n scripts/uninstall-helper.sh && echo syntax-ok; scripts/install-helper.sh; echo "exit=$?"`
Expected: `Build complete!`, `syntax-ok`, then `관리자 권한이 필요합니다: sudo scripts/install-helper.sh` and `exit=1`.

- [ ] **Step 8: Run all tests and commit**

Run: `$SWIFT test --disable-xctest 2>&1 | tail -1`
Expected: `Test run with 43 tests in 9 suites passed`.

```bash
git add Package.swift Sources/BatteryCore/HelperPolicy.swift Sources/BatteryPlatform/ChargeHelperXPC.swift Sources/VBChargeHelper Sources/MacBridge scripts/install-helper.sh scripts/uninstall-helper.sh Tests/BatteryCoreTests/HelperPolicyTests.swift
git commit -m "feat: add bounded root helper for sub-80 charge limits"
```

---

### Task 6: Preferences, charge-control card, heat loop, login item

**Files:**
- Modify: `Sources/BatteryCore/UserPreferences.swift`
- Modify: `Sources/VibeBattery/AppModel.swift`
- Create: `Sources/VibeBattery/ChargeControlView.swift`
- Modify: `Sources/VibeBattery/DashboardView.swift` (replace the "충전 보호 설정" card)
- Modify: `Sources/VibeBattery/SettingsView.swift` (heat settings, login item, feature status text)
- Modify: `Sources/VibeBattery/App.swift` (menu line)
- Test: `Tests/BatteryCoreTests/PreferencesTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces: `UserPreferences.heat: HeatSettings`; AppModel `charge`, `chargeConflicts`, `chargeOrigin`, `helperInstalled`, `topUpRequested`, `heatStatus`, `loginItem`, `applyCharge(_:)`, `setHeatEnabled(_:)`, `setLoginItem(_:)`, `helperInstallCommand`.

- [ ] **Step 1: Write the failing tests**

Append to `PreferencesTests`:

```swift
    @Test func legacyPreferencesKeepChoices() throws {
        let old=#"{"hours":8,"screenOff":false,"cleanup":true,"backgroundHistory":false}"#
        let p=try JSONDecoder().decode(UserPreferences.self,from:Data(old.utf8))
        #expect(p.hours==8);#expect(!p.screenOff);#expect(p.cleanup);#expect(!p.backgroundHistory)
        #expect(p.heat==HeatSettings())
    }
    @Test func heatSettingsAreValidatedWithPreferences() {
        var p=UserPreferences();p.heat.holdAt=60;p.heat.resumeAt=70;p.validate()
        #expect(p.heat.holdAt==35);#expect(p.heat.resumeAt==32)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `$SWIFT test --disable-xctest --filter PreferencesTests 2>&1 | tail -5`
Expected: build FAILS with `value of type 'UserPreferences' has no member 'heat'`.

- [ ] **Step 3: Implement preferences**

Replace the struct in `Sources/BatteryCore/UserPreferences.swift` (keep `ShellQuote`):

```swift
public struct UserPreferences: Codable {
    public var hours=4.0;public var screenOff=true;public var cleanup=false;public var backgroundHistory=true
    public var heat=HeatSettings()
    public init() {}
    // Files written before a field existed must keep the user's other choices.
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        hours=try c.decodeIfPresent(Double.self,forKey:.hours) ?? 4
        screenOff=try c.decodeIfPresent(Bool.self,forKey:.screenOff) ?? true
        cleanup=try c.decodeIfPresent(Bool.self,forKey:.cleanup) ?? false
        backgroundHistory=try c.decodeIfPresent(Bool.self,forKey:.backgroundHistory) ?? true
        heat=try c.decodeIfPresent(HeatSettings.self,forKey:.heat) ?? HeatSettings()
    }
    public mutating func validate() { if !hours.isFinite || hours<=0 || hours>168 { hours=4 };heat.validate() }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `$SWIFT test --disable-xctest 2>&1 | tail -3`
Expected: `Test run with 45 tests in 9 suites passed`.

- [ ] **Step 5: Wire the app model**

In `Sources/VibeBattery/AppModel.swift` add `import ServiceManagement`, and inside `AppModel`:

```swift
    @Published var charge=ChargeLimitState()
    @Published var chargeConflicts:[OtherChargeController]=[]
    @Published var loginItem=false
    private var lastHeatAction=HeatAction.none
    private let chargeController=ChargeController(backend:PowerUIChargeBackend(),helper:XPCChargeHelper(),detect:ChargeControllerScan.current,url:AppPaths.directory.appendingPathComponent("charge.json"))
    var chargeOrigin:LimitOrigin { charge.origin(lastWritten:chargeController.record.lastWritten) }
    var helperInstalled:Bool { chargeController.helperInstalled }
    var topUpRequested:Date? { chargeController.record.topUpRequested }
    var helperInstallCommand:String { "sudo /Applications/VibeBattery.app/Contents/Resources/install-helper.sh" }
    var heatStatus:String {
        let h=preferences.heat
        if !h.enabled { return "꺼짐" }
        if chargeController.record.heatPaused { return "적용 실패로 멈춤 · 다시 켜거나 상한을 적용하면 재개" }
        if let hold=chargeController.record.heat.holdLimit { return "보류 중 · 상한을 \(hold)%로 낮춤, \(Int(h.resumeAt))°C 이하 5분 유지 시 복원" }
        switch lastHeatAction {
        case .sensorUnavailable:return "중지됨 · 배터리 온도를 읽지 못함"
        case .cannotHold:return "보류 불가 · 잔량 50% 미만이거나 80% 미만 보류에 헬퍼가 필요"
        default:return "감시 중 · \(Int(h.holdAt))°C 이상 충전 시 보류 (앱 실행 중에만)"
        }
    }
    func refreshCharge() {
        let step=chargeController.heatStep(snapshot:battery,settings:preferences.heat)
        lastHeatAction=step.action
        if case .failure(let e)?=step.result { message="과열 보류를 멈췄습니다. \(e.localizedDescription)" }
        charge=chargeController.state();chargeConflicts=ChargeControllerScan.current()
        loginItem=SMAppService.mainApp.status == .enabled
    }
    func applyCharge(_ c:ChargeCommand) {
        switch chargeController.apply(c) {
        case .success(let s):
            charge=s
            message = c == .startTopUp ? "한 번 완충을 요청했습니다. 원래 상한으로 돌아가는 시점은 macOS가 정합니다.":"적용을 확인했습니다. \(ChargeText.limit(s))"
        case .failure(let e):message=e.localizedDescription
        }
    }
    func setHeatEnabled(_ on:Bool) {
        preferences.heat.enabled=on;if on { chargeController.resumeHeat() };savePreferences();refreshCharge()
    }
    func setLoginItem(_ on:Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { message="로그인 시 실행 설정 실패: \(error.localizedDescription)" }
        loginItem=SMAppService.mainApp.status == .enabled
    }
```

At the end of `refresh()` add `refreshCharge()`.

- [ ] **Step 6: Add the charge-control card**

`Sources/VibeBattery/ChargeControlView.swift`:

```swift
import SwiftUI
import BatteryCore
import BatteryPlatform
struct ChargeControlCard:View {
    @EnvironmentObject var model:AppModel
    @State private var target=80
    var canWrite:Bool { model.charge.supported==true && model.chargeConflicts.isEmpty }
    var needsHelper:Bool { target<ChargeCommand.userFloor && !model.helperInstalled }
    var originText:String {
        switch model.chargeOrigin {
        case .vibeBattery:return "VibeBattery가 설정"
        case .external:return "다른 앱 또는 시스템 설정에서 설정"
        case .none:return "상한 없음"
        case .unknown:return "확인 불가"
        }
    }
    var body:some View {
        Card {
            HStack { Label("충전 제어",systemImage:"shield.lefthalf.filled").font(.headline);Spacer();Text(originText).font(.caption).foregroundStyle(.secondary) }
            Text(ChargeText.limit(model.charge)).font(.system(size:27,weight:.semibold,design:.rounded))
            if !model.chargeConflicts.isEmpty {
                Label("\(model.chargeConflicts.map(\.name).joined(separator:", "))이(가) 충전을 관리하고 있어 VibeBattery는 값을 바꾸지 않습니다. 해당 앱을 종료하거나 삭제하면 제어할 수 있습니다.",systemImage:"exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            HStack(spacing:12) {
                Stepper("상한 \(target)%",value:$target,in:ChargeCommand.range,step:5).frame(maxWidth:180)
                Button("적용") { model.applyCharge(.setLimit(target)) }.buttonStyle(.borderedProminent).disabled(!canWrite || needsHelper)
                Button("상한 끄기") { model.applyCharge(.clearLimit) }.disabled(!canWrite)
            }
            if needsHelper { Text("80% 미만은 헬퍼 설치 후 사용할 수 있습니다. 터미널에서 실행: \(model.helperInstallCommand)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack(spacing:12) {
                Button("한 번 100% 충전") { model.applyCharge(.startTopUp) }.disabled(!canWrite)
                if model.topUpRequested != nil { Button("완충 종료") { model.applyCharge(.endTopUp) }.disabled(!canWrite) }
            }
            Text("과열 보류: \(model.heatStatus)").font(.callout)
            Text("헬퍼 \(model.helperInstalled ? "설치됨":"설치 안 됨") · 상한은 앱을 종료해도 macOS가 유지합니다.").font(.caption).foregroundStyle(.secondary)
            Text("항해 하한 지정·강제 방전·교정은 이 macOS 펌웨어에서 어댑터 차단 없이 불가능해 제공하지 않습니다. 재충전 시점은 macOS가 정합니다.").font(.caption).foregroundStyle(.secondary)
        }.onAppear { target=model.charge.limit.map { min(100,max(50,$0)) } ?? 80 }
    }
}
```

In `DashboardView.swift`, replace the last `Card { Label("충전 보호 설정", ...) ... }` block with `ChargeControlCard()`.

- [ ] **Step 7: Settings and menu**

In `SettingsView.swift`, replace the first card ("충전과 에너지 모드") with:

```swift
        Card {
            Text("과열 시 충전 보류").font(.headline)
            Toggle("배터리 온도가 높으면 충전 보류",isOn:Binding(get:{ model.preferences.heat.enabled },set:{ model.setHeatEnabled($0) }))
            Stepper("보류 온도 \(Int(model.preferences.heat.holdAt))°C",value:$model.preferences.heat.holdAt,in:30...45,step:1).onChange(of:model.preferences.heat.holdAt) { _,_ in model.savePreferences() }
            Stepper("재개 온도 \(Int(model.preferences.heat.resumeAt))°C",value:$model.preferences.heat.resumeAt,in:25...44,step:1).onChange(of:model.preferences.heat.resumeAt) { _,_ in model.savePreferences() }
            Text("기본값 35°C/32°C는 Apple 공식 기준이 아닌 보수적 설계값입니다. 잔량 50% 이상에서 충전 중일 때만 상한을 현재 잔량으로 낮추며, 앱이 실행 중일 때만 동작합니다. Apple의 하드웨어 보호를 대체하지 않습니다.").font(.caption).foregroundStyle(.secondary)
        }
        Card {
            Text("시작과 에너지 모드").font(.headline)
            Toggle("로그인 시 VibeBattery 실행",isOn:Binding(get:{ model.loginItem },set:{ model.setLoginItem($0) }))
            Text("저전력·자동·고전력 모드는 macOS 배터리 설정에서 선택합니다.").foregroundStyle(.secondary)
            Button("시스템 배터리 설정 열기") { model.openBatterySettings() }
        }
```

and change the "개발 중" text in the last card to: `"제공: 충전 상한 50~100%, 한 번 완충, 과열 시 충전 보류. 미제공: 항해 하한 지정·강제 방전·교정(펌웨어 제약). 개발 예정: 일정·단축어, MagSafe LED."`.

In `App.swift` `MenuContent`, after the temperature line add `Text(ChargeText.limit(model.charge))` and add `import BatteryPlatform` at the top.

- [ ] **Step 8: Build, test, launch**

Run: `$SWIFT test --disable-xctest 2>&1 | tail -1 && VB_SWIFT=$SWIFT scripts/build-app.sh | tail -1 && open dist/VibeBattery.app && sleep 5 && pgrep -x VibeBattery`
Expected: `Test run with 45 tests in 9 suites passed`, `.../dist/VibeBattery.app`, and a PID (the app stays running). `build-app.sh` does not embed the helper yet; that is Task 7. Quit the app afterwards with `osascript -e 'quit app "VibeBattery"'`. No setting is changed by launching: AlDente is detected, so writes are blocked.

- [ ] **Step 9: Commit**

```bash
git add Sources/BatteryCore/UserPreferences.swift Sources/VibeBattery Tests/BatteryCoreTests/PreferencesTests.swift
git commit -m "feat: add charge control card, heat hold loop and login item"
```

---

### Task 7: Bundle the helper, CI, and documentation

**Files:**
- Modify: `scripts/build-app.sh`
- Modify: `.github/workflows/ci.yml`
- Modify: `README.md`, `docs/COMPATIBILITY.md`, `docs/VALIDATION.md`, `docs/superpowers/plans/2026-10-20-charge-control.md` (progress line)

**Interfaces:**
- Consumes: `VBChargeHelper` product (Task 5), scripts (Task 5).
- Produces: `dist/VibeBattery.app/Contents/MacOS/VBChargeHelper` signed with identifier `io.github.y-minion.vibebattery.helper`; `Contents/Resources/install-helper.sh`, `uninstall-helper.sh`.

- [ ] **Step 1: Write the failing check**

Run: `VB_SWIFT=$SWIFT scripts/build-app.sh >/dev/null && codesign -dv dist/VibeBattery.app/Contents/MacOS/VBChargeHelper 2>&1 | grep Identifier`
Expected: FAIL — `dist/VibeBattery.app/Contents/MacOS/VBChargeHelper: No such file or directory`.

- [ ] **Step 2: Embed and sign**

In `scripts/build-app.sh`, after copying `vbctl`:

```sh
cp "$VB_BIN_DIR/VBChargeHelper" "$VB_APP/Contents/MacOS/VBChargeHelper"
cp scripts/install-helper.sh scripts/uninstall-helper.sh "$VB_APP/Contents/Resources/"
```

and before `codesign --force --sign - "$VB_APP"`:

```sh
codesign --force --sign - --identifier io.github.y-minion.vibebattery.helper "$VB_APP/Contents/MacOS/VBChargeHelper"
```

- [ ] **Step 3: Verify**

Run: `VB_SWIFT=$SWIFT scripts/build-app.sh | tail -1; codesign -dv dist/VibeBattery.app/Contents/MacOS/VBChargeHelper 2>&1 | grep '^Identifier'; codesign -dv dist/VibeBattery.app 2>&1 | grep '^Identifier'; ls dist/VibeBattery.app/Contents/Resources; dist/VibeBattery.app/Contents/MacOS/vbctl charge status`
Expected:
```
.../dist/VibeBattery.app
Identifier=io.github.y-minion.vibebattery.helper
Identifier=io.github.y-minion.vibebattery
install-helper.sh
uninstall-helper.sh
충전: 현재 상한 79%
다른 충전 관리: AlDente (실행 중: com.apphousekitchen.aldente-pro)
```

- [ ] **Step 4: CI**

In `.github/workflows/ci.yml` add after "Build app bundle":

```yaml
      - name: Check helper scripts
        run: sh -n scripts/install-helper.sh && sh -n scripts/uninstall-helper.sh
      - name: Read charge limit (read-only, runner may report unsupported)
        run: dist/VibeBattery.app/Contents/MacOS/vbctl charge status
```

- [ ] **Step 5: Documentation**

- `docs/COMPATIBILITY.md`: replace the "Charge cap / power modes" and "Sailing / heat charging pause / calibration / MagSafe LED" rows with:
  - `| Charge limit 80–100% | macOS charge limit through private PowerUI client; write verified by read-back. Hardware write validation: see VALIDATION.md |`
  - `| Charge limit 50–79% | Optional root helper writing com.apple.smartcharging.topoffprotection; bounded to setLimit/readState; ad-hoc identifier-only client check |`
  - `| One-time full charge | PowerUI temporary disable; return timing decided by macOS |`
  - `| Heat charging hold | Lowers the limit to current charge at ≥ hold temperature while charging and ≥ 50%; app must be running; restores only its own value |`
  - `| Sailing lower bound / forced discharge / calibration | Not available: firmware 20457.1.29 blocks SMC charge keys; only adapter cutoff remains, which conflicts with battery preservation |`
  - `| Other charge managers | AlDente/batt detected by running app or installed daemon; all writes blocked |`
  - Keep `| Power modes | Opens macOS Battery settings |` and the MagSafe LED row as "Planned (ACLC readable, write unverified)".
  Also add a "Firmware findings (2026-10-20)" paragraph summarising spec section 2.
- `README.md`: in 현재 기능 add the four charge bullets; replace the sentence starting "충전 상한과 에너지 모드는 macOS 배터리 설정으로 연결합니다" with the limits of the firmware; add a "충전 헬퍼" section with the install/uninstall commands and the note that the helper only accepts the app in `/Applications`.
- `docs/VALIDATION.md`: add "Charge control (2026-10-20)" listing the automated tests (count from Step 6) and the read-only on-device check; state that hardware writes are pending Task 8.
- Plan header: add `**Progress:** Tasks 1–7 complete; Task 8 (hardware) pending user presence.`

- [ ] **Step 6: Full verification and commit**

Run: `$SWIFT test --disable-xctest 2>&1 | tail -1 && python3 scripts/smoke-sessions.py .build/debug/vbctl 2>&1 | tail -1 && python3 scripts/smoke-sessions.py dist/VibeBattery.app/Contents/MacOS/vbctl 2>&1 | tail -1 && git ls-files | grep -E '^work/|\.log$' ; echo tracked-check-done`
Expected: `Test run with 45 tests in 9 suites passed`, both smoke runs end with their success line, no `work/` or log files listed, `tracked-check-done`.

```bash
git add scripts/build-app.sh .github/workflows/ci.yml README.md docs
git commit -m "build: bundle charge helper and document charge control limits"
```

- [ ] **Step 7: Publish to the PR**

```bash
git push origin feat/native-app
gh pr checks 1 --watch
```
Expected: `test` check passes. Update the PR description with a "Charge control" section (what is verified, what waits for Task 8).

---

### Task 8: Hardware validation (requires the user at the Mac)

**Stop before this task and ask the user.** It needs sudo, the user's removal of AlDente, and must not run remotely.

**Files:**
- Modify: `docs/VALIDATION.md`, `docs/COMPATIBILITY.md` (record observed results)

- [ ] **Step 1: Record the starting state**

Run: `dist/VibeBattery.app/Contents/MacOS/vbctl charge status --json; pmset -g battlimit | grep -E 'chargeSocLimitSoc|Owner'`
Record both outputs in the ledger. This is the value to restore at the end unless the user chooses otherwise.

- [ ] **Step 2: User removes AlDente**

User quits AlDente and uninstalls it with its own uninstaller (removing its helper). Then run `vbctl charge status`.
Expected: no "다른 충전 관리" line. Record whether the limit (79%) persisted after AlDente's removal.

- [ ] **Step 3: Install app and helper**

User: copy `dist/VibeBattery.app` to `/Applications`, then `sudo /Applications/VibeBattery.app/Contents/Resources/install-helper.sh`.
Expected: `설치했습니다: io.github.y-minion.vibebattery.helper`; `sudo launchctl print system/io.github.y-minion.vibebattery.helper | head -3` shows the service.

- [ ] **Step 4: 80–100 write**

In the app: set 85 → 적용. Expected alert `적용을 확인했습니다. 현재 상한 85%`; `vbctl charge status` and `pmset -g battlimit` both show 85.

- [ ] **Step 5: Sub-80 write via helper**

In the app: set 75 → 적용 (Stepper from 85 in steps of 5, or start at 79 and step down). Expected `현재 상한 75%`, `pmset -g battlimit` shows 75. If it reports `적용 실패`, run `sudo defaults read com.apple.smartcharging.topoffprotection` and record the keys/types; this is the planned discovery point for the `MCLFeatureState` encoding — rule on it in the ledger before changing `TopoffDomain.writes`.

- [ ] **Step 6: One-time full charge**

Press "한 번 100% 충전". Record `vbctl charge status --json` and `pmset -g battlimit` immediately and after 1 minute. Press "완충 종료". Expected: MCL re-enabled at the previous limit. Record the observed macOS behaviour verbatim.

- [ ] **Step 7: Persistence**

Quit the app → `vbctl charge status` still shows the limit. Sleep and wake → still shown. Reboot (user's choice, may be deferred) → still shown. Record each result or "deferred".

- [ ] **Step 8: Restore and document**

Restore the starting value from Step 1 (or the user's chosen value) through the app. Update `docs/VALIDATION.md` with every observation (pass/fail/deferred), and `docs/COMPATIBILITY.md` rows from "pending" to "verified on target" only for items that passed. Run `$SWIFT test --disable-xctest`, commit `docs: record charge control hardware validation`, push, and confirm CI.
