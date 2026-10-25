# Free Pro Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Live menu bar status icon, a customizable menu bar window, power flow, hardware percentage, a Low Power Mode switch and (if the hardware test passes) MagSafe LED control.

**Architecture:**
- Pure rules live in `BatteryCore` and are tested there: status, section order, power split, hardware percentage, `pmset` parsing and LED values.
- IORegistry reads extend `BatterySnapshot.decode`.
- The helper (protocol version 2) gains two fixed requests: Low Power Mode via `pmset` argv, and one SMC key `ACLC` through a new MacBridge SMC function.
- The app's `MenuBarExtra` switches to `.window` style. All UI reads `AppModel.shared`.

**Tech Stack:** Swift 6, SwiftUI, AppIntents, IOKit (AppleSMC user client), Swift Testing, Xcode 27.1 / XcodeGen project.

**Spec:** `docs/superpowers/specs/2026-10-25-pro-features-design.md`

## Global Constraints

- Charge writes (limit, top-up) stay blocked while another charge manager is present, are read back, and are logged with their source. Quick-limit buttons use `AppModel.applyCharge` (source `user`).
- SMC writes: only key `ACLC`, only values 0 (system), 1 (off), 3 (green), 4 (orange). The key is a constant in code. Before writing, its type must be `ui8` and its size 1. Charging SMC keys are never written.
- LED writes are blocked while another charge manager is present. LED and Low Power writes are not added to `charge.json`.
- The helper accepts only fixed requests. There is no generic command, no arbitrary key and no shell. Caller checks are unchanged (`HelperPolicy.allows`, `clientRequirement`).
- `HelperPolicy.protocolVersion = 2`. A helper that does not answer `version` counts as version 1. Limit writes keep working with version 1.
- Screen text is Korean and plain. "SMC", "ACLC", "PowerTelemetry" and "pmset" never appear on screen.
- Unreadable power values are hidden, never estimated.
- Minimum macOS 15. `swift test`, `swift build`, `scripts/smoke-sessions.py`, `scripts/build-app.sh` and CI keep passing.
- Menu window default: sections ① status ② power ③ limit ⑤ lowPower ⑥ battery ⑦ sessions visible, ④ topUp hidden. Icon default: icon + percent.
- No personal device values in code or test fixtures (this Mac's readings are synthetic in tests).

## Review Focus

1. A preferences file from 0.1 (no `menuBar`, no `led`) must load with defaults and keep every other setting (Task 2: `oldPreferencesKeepOtherSettings`).
2. Power telemetry present but the Mac on battery (`SystemPowerIn` 0) must show only battery → Mac, not a 0 W adapter bar (Task 1: `onBatteryIgnoresAdapterKeys`).
3. An old (version 1) helper must not break limit writes, and the app must show "헬퍼 업데이트 필요" for Low Power and LED (Task 3: `oldHelperIsOutdatedButCanSetLimit`).
4. With the LED on "macOS 기본", a crash after a non-system write must be cleaned up on the next launch, exactly once (Task 7: `dirtyFlagResetsOnceOnLaunch`).
5. The LED must not be rewritten on every 5 s tick when nothing changed (Task 7: `sameStateWritesNothing`).

---

### Task 1: Power flow and hardware percentage readings

**Files:**
- Create: `Sources/BatteryCore/PowerFlow.swift`
- Modify: `Sources/BatteryCore/BatterySnapshot.swift`
- Test: `Tests/BatteryCoreTests/PowerFlowTests.swift`

**Interfaces:**
- Produces:
  - `BatterySnapshot.hardwarePercent: Int?`, included in `CodingKeys` (so `vbctl status --json` gains the field).
  - `BatterySnapshot.power: PowerReading?`, excluded from `CodingKeys` (like `batteryID`).
  - `struct PowerReading: Equatable, Sendable { var adapterName: String?; var adapterWatts: Int?; var inputW: Double?; var systemW: Double? }`
    - `inputW` = `PowerTelemetryData.SystemPowerIn / 1000`
    - `systemW` = `SystemLoad / 1000`
    - `adapterWatts` and `adapterName` come from `AdapterDetails.Watts` and `.Name`, with whitespace trimmed
  - `enum PowerSegment: Equatable, Sendable { case adapterToMac(Double), adapterToBattery(Double), batteryToMac(Double) }` with `var label: String`
  - `struct PowerSummary: Equatable, Sendable { var headline: String; var adapter: String?; var segments: [PowerSegment] }`
  - `static func PowerSummary.make(_ b: BatterySnapshot) -> PowerSummary?`

Rules for `make`:
- Let `battery = b.watts`; positive means charging. "Idle" is `|battery| < 0.5`.
- On AC, it needs `inputW > 0`; otherwise return nil.
  - Charging: `[.adapterToMac(max(0, input - battery)), .adapterToBattery(battery)]`. Headline: `"충전기에서 \(W) W 들어옴"`.
  - Idle: `[.adapterToMac(input)]`, with the same headline.
  - Discharging: `[.adapterToMac(input), .batteryToMac(-battery)]`. Headline: `"충전기 \(W) W + 배터리 \(W) W 사용"`.
- Off AC, it needs a non-nil `battery`; otherwise return nil. The result is `[.batteryToMac(abs(battery))]`, headline `"배터리에서 \(W) W 사용"`. Adapter keys are ignored.
- Watts are formatted `%.0f`.
- Labels:
  - `adapterToMac`: `"맥 18 W"`
  - `adapterToBattery`: `"배터리 +14 W"`
  - `batteryToMac`: `"배터리에서 5 W"`
- `adapter` is `"70W USB-C"`: `"\(adapterWatts)W"`, plus `" " + name` when the name exists, with "Power Adapter" removed.
- `hardwarePercent` = `BatteryData.RemainingCapacity / BatteryData.FullChargeCapacity × 100`, rounded. It is nil if the denominator is 0 or the result falls outside 0…100.

- [ ] Step 1: write the tests:

```swift
@Test func chargingSplitsInput() {
    var b=BatterySnapshot();b.onAC=true;b.charging=true;b.watts=14
    b.power=PowerReading(adapterName:"70W USB-C Power Adapter",adapterWatts:70,inputW:32,systemW:18)
    let s=PowerSummary.make(b)!
    #expect(s.headline=="충전기에서 32 W 들어옴");#expect(s.adapter=="70W USB-C")
    #expect(s.segments==[.adapterToMac(18),.adapterToBattery(14)])
    #expect(s.segments.map(\.label)==["맥 18 W","배터리 +14 W"])
}
@Test func pausedIsAdapterOnly()      // onAC, watts 0.2, input 8.8 → [.adapterToMac(8.8)]
@Test func pluggedDischargeShowsBoth() // onAC, watts -5, input 20 → [.adapterToMac(20),.batteryToMac(5)], headline "충전기 20 W + 배터리 5 W 사용"
@Test func onBatteryIgnoresAdapterKeys() // onAC false, watts -7, inputW 0 → [.batteryToMac(7)], headline "배터리에서 7 W 사용"
@Test func missingKeysGiveNil()       // power nil → nil; onAC with inputW nil → nil; off AC with watts nil → nil
@Test func hardwarePercentFromRawCapacity() // decode ["BatteryData":["RemainingCapacity":3569,"FullChargeCapacity":5332]] → 67; FullChargeCapacity 0 → nil; Remaining > Full ×1.01 → nil
@Test func decodeReadsTelemetry()     // decode with PowerTelemetryData SystemPowerIn 8754, SystemLoad 8754, AdapterDetails Watts 70 → inputW 8.754, adapterWatts 70
```

- [ ] Step 2: run `swift test --filter PowerFlowTests`. Expected: it fails to compile.
- [ ] Step 3: implement as specified above.
- [ ] Step 4: run `swift test`. Expected: all pass.
- [ ] Step 5: commit `feat: read power flow and hardware battery percentage`.

### Task 2: Menu bar status and menu settings

**Files:**
- Create: `Sources/BatteryCore/MenuBarSettings.swift`
- Modify: `Sources/BatteryCore/UserPreferences.swift` (adds `menuBar`; decoded with `decodeIfPresent ?? MenuBarSettings()`)
- Test: `Tests/BatteryCoreTests/MenuBarSettingsTests.swift`

**Interfaces:**
- Produces:
  - `enum MenuBarStatus: Equatable, Sendable { case charging, paused, onBattery, heatHold; static func make(onAC: Bool, charging: Bool, heatHolding: Bool) -> MenuBarStatus }`. `heatHold` comes first, then `charging`, then `paused` (`onAC`), then `onBattery`.
  - `enum MenuIconStyle: String, Codable, CaseIterable, Sendable { case iconAndPercent, iconOnly, percentOnly }` with `var title: String`: "아이콘 + 잔량", "아이콘만", "잔량만".
  - `enum MenuSection: String, Codable, CaseIterable, Sendable { case status, power, limit, topUp, lowPower, battery, sessions }` with:
    - `var title: String`: "잔량과 상태", "전력 흐름", "충전 상한 바로 바꾸기", "한 번 완충과 다음 일정", "저전력 모드", "배터리 정보", "바이브 코딩 작업"
    - `var defaultVisible: Bool`: false only for `topUp`
  - `struct MenuSectionSetting: Codable, Equatable, Sendable { var section: MenuSection; var visible: Bool }`
  - `struct MenuBarSettings: Codable, Equatable, Sendable`:
    - `var icon: MenuIconStyle = .iconAndPercent`
    - `var sections: [MenuSectionSetting]`; the default is every case in declaration order with `defaultVisible`
    - `mutating func move(_ s: MenuSection, by offset: Int)`, clamped to the list
    - `static let `default``
  - Decoding is lossy:
    - unknown section strings are dropped
    - duplicates keep the first occurrence
    - missing cases are appended with `defaultVisible`
    - an unknown icon style falls back to the default
  - `static func MenuQuick.limits` = `[60,70,80,90,100]`

- [ ] Step 1: write the tests:
  - `statusPrecedence`: `make(onAC:true, charging:true, heatHolding:true) == .heatHold`; `(true, true, false) == .charging`; `(true, false, false) == .paused`; `(false, false, false) == .onBattery`.
  - `defaultSections`: visible sections equal `[.status,.power,.limit,.lowPower,.battery,.sessions]`, and `topUp` is hidden.
  - `decodeDropsUnknownAndAppendsMissing`: the JSON `{"icon":"weird","sections":[{"section":"battery","visible":false},{"section":"ghost","visible":true},{"section":"battery","visible":true}]}` gives `icon == .iconAndPercent`, `sections.first == .init(section:.battery, visible:false)`, `sections.count == 7`, and the appended `topUp` hidden.
  - `moveClamps`: moving `.status` by -1 does nothing; moving it by +1 swaps it with `.power`.
  - `oldPreferencesKeepOtherSettings`: `UserPreferences` JSON without `menuBar`, with `hours: 6`, decodes with `hours == 6` and `menuBar == .default`.
- [ ] Step 2: run `swift test --filter MenuBarSettingsTests`. Expected: it fails to compile.
- [ ] Step 3: implement.
- [ ] Step 4: run `swift test`. Expected: all pass.
- [ ] Step 5: commit `feat: model the menu bar status and window sections`.

### Task 3: Helper protocol v2 (Low Power, MagSafe LED, version) and the LED hardware gate

**Files:**
- Modify:
  - `Sources/MacBridge/include/MacBridge.h`, `Sources/MacBridge/MacBridge.c` (or a new `Sources/MacBridge/SMC.c`)
  - `Package.swift` and `project.yml`: link IOKit for MacBridge, then run `xcodegen generate`
  - `Sources/BatteryCore/HelperPolicy.swift`
  - `Sources/BatteryPlatform/ChargeHelperXPC.swift`
  - `Sources/VBChargeHelper/main.swift`
  - `scripts/uninstall-helper.sh`
  - `Sources/VibeBattery/ChargeControlView.swift`: the `.outdated` text
- Create: `Sources/BatteryCore/LowPowerSettings.swift`
- Test: `Tests/BatteryCoreTests/HelperV2Tests.swift`

**Interfaces:**
- Produces (BatteryCore):
  - `HelperPolicy.protocolVersion = 2`
  - `enum MagSafeLED: Int, Codable, CaseIterable, Sendable { case system=0, off=1, green=3, orange=4 }`. `MagSafeLED(rawValue:)` is the allow-list.
  - `struct LowPowerSettings: Equatable, Sendable { var key: String?; var battery: Int?; var ac: Int?; static func parse(_ pmsetCustom: String) -> LowPowerSettings; var isConditional: Bool; func arguments(on: Bool) -> [String]? }`
    - Parse the `Battery Power:` and `AC Power:` blocks of `pmset -g custom`.
    - `key` is `powermode` when present, else `lowpowermode`, else nil.
    - `isConditional` is true when `battery != ac`.
    - `arguments(on:)` is `["-a", key, on ? "1":"0"]`, or nil without a key.
  - `HelperStatus` gains `.outdated`. `evaluate(installed:appPath:probe:version:)` returns `.outdated` when the probe succeeds and `(version() ?? 1) < protocolVersion`. Add `var canSetLimit: Bool { self == .ready || self == .outdated }`.
- Produces (MacBridge):
  - `int vb_smc_read_u8(const char *key, uint8_t *out)` and `int vb_smc_write_u8(const char *key, uint8_t value)`.
  - Each opens `AppleSMC` and reads the key info first. It returns -2 unless the type is `ui8` and the size is 1.
  - Return codes: 0 ok, -1 open failed, -2 wrong type/size, -3 SMC call failed.
  - Use the standard AppleSMC user-client struct (`SMCKeyData_t`, selector 2, commands 9 = key info, 5 = read, 6 = write).
- Produces (BatteryPlatform):
  - `ChargeHelperProtocol` gains `version(reply:(Int)->Void)`, `setLowPowerMode(_ on:Bool, reply:(String?)->Void)` and `setMagSafeLED(_ raw:Int, reply:(String?)->Void)`.
  - `XPCChargeHelper` gains `helperVersion() -> Int?`, `setLowPowerMode(_ on:Bool) -> String?` and `setMagSafeLED(_ v:MagSafeLED) -> String?`.
  - `status(probe:)` passes `helperVersion` for `version`. `isInstalled` uses `canSetLimit`.
- Helper:
  - `setLowPowerMode` runs `/usr/bin/pmset -g custom`, parses it, then runs `/usr/bin/pmset` with `arguments(on:)` via `Process` (argv, no shell). It replies with an error text when there is no key or the exit code is non-zero.
  - `setMagSafeLED` rejects a raw value outside `MagSafeLED`, then calls `vb_smc_write_u8("ACLC", raw)`.
  - Root-only command line, used only when the binary is started directly rather than by launchd: `--led read|system|off|green|orange`. It prints `"ACLC 이전 값 N"` and, for writes, `"→ M"`, then exits. Exit codes: 0 ok, 1 failure, 2 usage. With no arguments the helper runs the XPC listener as today.
- `uninstall-helper.sh` runs `"$DEST" --led system || true` before `bootout`.
- `HelperStatus.evaluate` keeps its old call shape: `version` defaults to `{ HelperPolicy.protocolVersion }`, so existing `HelperPolicyTests` still compile.
- The `.outdated` text in `ChargeControlView`: "헬퍼 업데이트 필요 · 저전력 모드와 MagSafe LED를 쓰려면 다시 설치하세요: \(model.helperInstallCommand)". Every other `switch` over `HelperStatus` gets the new case.

- [ ] Step 1: write the tests:
  - `parsesPowermode`: input `"Battery Power:\n powermode            1\nAC Power:\n powermode            0\n"` gives `key == "powermode"`, `battery == 1`, `ac == 0`, `isConditional`, and `arguments(on:false) == ["-a","powermode","0"]`.
  - `parsesLegacyKey`: `lowpowermode` in both blocks with equal values gives `key == "lowpowermode"` and `!isConditional`.
  - `noKeyGivesNoArguments`: `arguments(on:true) == nil`.
  - `ledAllowList`: `MagSafeLED(rawValue:2) == nil` and `MagSafeLED.allCases.map(\.rawValue) == [0,1,3,4]`.
  - `oldHelperIsOutdatedButCanSetLimit`: `evaluate(installed:true, appPath:"/Applications/VibeBattery.app", probe:{true}, version:{nil}) == .outdated`, and `.outdated.canSetLimit`.
  - `currentHelperIsReady`: `version:{2}` gives `.ready`.
- [ ] Step 2: run `swift test --filter HelperV2Tests`. Expected: it fails to compile.
- [ ] Step 3: implement the BatteryCore, MacBridge, BatteryPlatform and helper pieces.
- [ ] Step 4: run `swift test`, then `scripts/build-app.sh | tail -1`. Expected: all pass, and the output ends with `dist/VibeBattery.app`.
- [ ] Step 5: **hardware gate**, with the user, on AC power with the MagSafe cable connected:
  1. Quit the app.
  2. `ditto --norsrc --noextattr dist/VibeBattery.app /Applications/VibeBattery.app`
  3. The user runs `sudo /Applications/VibeBattery.app/Contents/Resources/install-helper.sh`.
  4. The user runs `sudo /Library/PrivilegedHelperTools/io.github.y-minion.vibebattery.helper --led read`. Expected: exit 0 and a value.
  5. The user runs `… --led off` and confirms the LED is off.
  6. The user runs `… --led system` and confirms the LED is back.
  7. The user runs `… --led green`, then `… --led orange`, confirms the colors, then `… --led system`.
  8. Relaunch the app. Check that the charge page still shows "헬퍼 사용 가능" and that `vbctl charge set 70` returns exit 0.
  - **Any write error, unexpected value or failed restore:** stop. Run `… --led system` if the LED is not back. Remove `setMagSafeLED`, the `--led` option, both SMC functions, `MagSafeLED` and the uninstall-script line. Reinstall the helper. Record the result for Task 8 and skip Task 7.
- [ ] Step 6: commit `feat: helper protocol v2 with Low Power Mode and MagSafe LED requests` (if the gate failed: `feat: helper protocol v2 with Low Power Mode requests`).

### Task 4: Menu bar icon and window

**Files:**
- Create:
  - `Sources/VibeBattery/MenuBarIcon.swift`: icon drawing
  - `Sources/VibeBattery/MenuWindow.swift`: the window and its sections
- Modify:
  - `Sources/VibeBattery/App.swift`: replace `MenuLabel`'s body and `MenuContent`, and add `.menuBarExtraStyle(.window)`
  - `Sources/VibeBattery/AppModel.swift`: add `var menuStatus: MenuBarStatus` and `var activeSessions: [SessionRecord]`

**Interfaces:**
- Consumes:
  - `MenuBarStatus.make`, `MenuBarSettings`, `MenuQuick.limits` (Task 2)
  - `PowerSummary.make`, `BatterySnapshot.hardwarePercent` (Task 1)
  - `AppModel.applyCharge`, `AppModel.helperStatus.canSetLimit` (Task 3)
- Produces:
  - `struct PowerBar: View { let summary: PowerSummary; var compact: Bool }`, reused by Task 5. Segment colors: `adapterToMac` green, `adapterToBattery` blue, `batteryToMac` orange. Widths are proportional; a segment under 8% still shows at 8%.
  - `AppModel.menuStatus` = `MenuBarStatus.make(onAC: battery.onAC, charging: battery.charging, heatHolding: chargeController.record.heat.holdLimit != nil)`.
  - `AppModel.activeSessions` = `sessions.filter { $0.ended == nil && ownerAlive($0) }`.

Behavior:
- **Label**:
  - The battery outline is filled to `percent`, with the status glyph overlaid: bolt / plug / none / thermometer.
  - It is drawn as a template image, except in `heatHold`, which uses a non-template orange image.
  - `iconOnly` hides the text.
  - `percentOnly` shows the glyph character before `70%`: "⚡︎", "⏸︎", none, "🌡︎".
  - Keep the `onAppear` that sets `model.openMain`.
- **Window** (width about 300): the visible sections in `preferences.menuBar.sections` order, followed by the always-visible footer (대시보드 열기, Claude/Codex 명령 복사, 앱 종료).
  - **status**: a big percent. Its line is `ChargeText.limit(model.charge)` joined with " · " to the AC state ("충전기 연결"/"배터리 사용") and the temperature `%.1f°C`, when present.
  - **power**: `PowerBar(compact:true)`. The section is hidden when `PowerSummary.make` is nil.
  - **limit**: buttons for `MenuQuick.limits` plus "끄기".
    - The current enabled limit is highlighted only when it is in the list.
    - Every button is disabled when `charge.supported != true` or `!chargeConflicts.isEmpty`; show the reason in one line (the existing conflict text or "이 맥에서는 충전 상한을 바꿀 수 없습니다").
    - Values below 80 are disabled when `!helperStatus.canSetLimit`; show "80% 미만은 헬퍼가 필요합니다".
  - **topUp**: the existing "한 번 100% 충전"/"완충 종료" buttons and the next-schedule line from the current `MenuContent`.
  - **lowPower**: a placeholder row the task leaves for Task 6. Render nothing until Task 6 adds its view.
  - **battery**: three rows, "하드웨어 잔량", "건강도(추정)" and "사이클", each with "—" when nil.
  - **sessions**: "실행 중인 작업 N개", or "실행 중인 작업 없음". Add a line for the newest active session: the first word of `command` (basename) · "잠자기 방지 중" when `protected` · the elapsed time in minutes (`"42분"`).
- The window refreshes the battery every 2 s while it is open (`onAppear`/`onDisappear` toggling a model flag that the 5 s tick already reads). It stays at the normal cadence when closed.

- [ ] Step 1: `swift build`. Expected: Build complete.
- [ ] Step 2: `swift test`. Expected: all pass.
- [ ] Step 3: `scripts/build-app.sh | tail -1`, then install with `ditto` (quit the app first). Ask the user to check:
  - the icon while charging, paused at the limit and on battery
  - the window's six default sections
  - that tapping 70 when the limit is already 70 shows success
- [ ] Step 4: check that `charge.json`'s last log entry is `setLimit(70)` with source `user`.
- [ ] Step 5: commit `feat: show live status in the menu bar and a sectioned menu window`.

### Task 5: Settings card and dashboard

**Files:**
- Modify:
  - `Sources/VibeBattery/SettingsView.swift`: a new "메뉴 막대" card
  - `Sources/VibeBattery/DashboardView.swift`: replace the "배터리 전력 흐름" card, and add hardware percent to the battery card

**Interfaces:**
- Consumes: `MenuBarSettings` (Task 2), `PowerBar` and `PowerSummary` (Tasks 1 and 4).

Behavior:
- **Settings card "메뉴 막대"**:
  - an icon `Picker` over `MenuIconStyle.allCases`
  - one row per section: title, a `Toggle` for visible, and up/down buttons (`move(by: ±1)`, disabled at the ends)
  - a "기본값으로 되돌리기" button that sets `.default`
  - every change calls `savePreferences()`
- **Dashboard power card "전력 흐름"**:
  - the headline and adapter text, then `PowerBar(compact:false)`, then a legend line
  - when `PowerSummary.make` is nil: "이 맥에서는 전력 흐름을 읽을 수 없습니다"
- **Dashboard battery card**: under "충전 중"/"현재 충전하지 않음", add `"하드웨어 잔량 67%"` when it exists, with the spec's caption as `.help`: "macOS는 배터리 보호를 위해 표시 값을 조정합니다. 이 값은 배터리가 직접 보고한 남은 용량입니다."
- Move "배터리 설정 열기" out of the old menu. Add it as a button on the dashboard battery card.

- [ ] Step 1: `swift build` and `swift test`. Expected: both pass.
- [ ] Step 2: build and install. Ask the user to hide ⑥ and move ⑦ up, then quit and relaunch the app. Expected: the window keeps the change.
- [ ] Step 3: commit `feat: customize the menu window and show power flow on the dashboard`.

### Task 6: Low Power Mode switch and Shortcut

**Files:**
- Create: `Sources/VibeBattery/LowPowerView.swift`
- Modify:
  - `Sources/VibeBattery/AppModel.swift`
  - `Sources/VibeBattery/MenuWindow.swift`: the `lowPower` section
  - `Sources/VibeBattery/DashboardView.swift`: a switch row in the battery card
  - `Sources/VibeBattery/ChargeIntents.swift`

**Interfaces:**
- Consumes: `XPCChargeHelper.setLowPowerMode`, `LowPowerSettings.parse`, `HelperStatus.ready` (Task 3).
- Produces:
  - `AppModel.lowPower: Bool` (`@Published`), from `ProcessInfo.processInfo.isLowPowerModeEnabled`. It is updated on `.NSProcessInfoPowerStateDidChange`, observed on the main queue.
  - `AppModel.lowPowerConditional: Bool`. On refresh, run `/usr/bin/pmset -g custom` (no root) and `parse(...).isConditional`.
  - `AppModel.setLowPower(_ on: Bool) -> String?`. It returns nil on success, otherwise the message.
    - It requires `helperStatus == .ready`; otherwise it returns "헬퍼를 업데이트하면 여기서 바로 바꿀 수 있습니다."
    - It calls the helper, then polls `isLowPowerModeEnabled` for up to 2 s.
    - On a mismatch it returns "저전력 모드를 바꾸지 못했습니다."
  - `SetLowPowerModeIntent`: title "저전력 모드 설정", `@Parameter(title:"켜기", default:true) var on: Bool`, `openAppWhenRun=false`.
    - On success its dialog is "저전력 모드를 켰습니다." or "저전력 모드를 껐습니다."; failure throws `ShortcutFailure`.
    - It is not added to `VibeBatteryShortcuts`.
- `LowPowerView`, used in both places:
  - When `helperStatus == .ready`: a `Toggle("저전력 모드")`. When `lowPowerConditional`, add the caption "지금은 배터리/전원 어댑터에 따라 다르게 설정되어 있습니다. 여기서 바꾸면 항상 켜짐 또는 항상 꺼짐이 됩니다."
  - Otherwise: a "배터리 설정 열기" button (`openBatterySettings`) and the caption "헬퍼를 설치하면 여기서 바로 바꿀 수 있습니다". When the status is `.outdated`, the caption is "헬퍼 업데이트가 필요합니다".
- Low Power is not blocked by charge conflicts.

- [ ] Step 1: `swift build` and `swift test`. Expected: both pass.
- [ ] Step 2: build and install (the helper from Task 3 is already installed). Ask the user to check:
  - turning the switch on makes System Settings › Battery show low power mode on
  - turning it off reverts it
  - changing it in System Settings moves the switch within a few seconds
  - the Shortcut "저전력 모드 설정" works with on and with off
- [ ] Step 3: commit `feat: switch Low Power Mode from the app and Shortcuts`.

### Task 7: MagSafe LED (skip if the Task 3 gate failed)

**Files:**
- Create: `Sources/BatteryCore/MagSafeLEDPolicy.swift`
- Modify:
  - `Sources/BatteryCore/UserPreferences.swift`: adds `led`
  - `Sources/VibeBattery/AppModel.swift`
  - `Sources/VibeBattery/SettingsView.swift`: the "MagSafe LED" card
- Test: `Tests/BatteryCoreTests/MagSafeLEDTests.swift`

**Interfaces:**
- Consumes: `MenuBarStatus` (Task 2), `MagSafeLED`, `XPCChargeHelper.setMagSafeLED` (Task 3).
- Produces:
  - `enum LEDColor: String, Codable, CaseIterable, Sendable { case green, orange, off; var led: MagSafeLED; var title: String }`. Titles: "초록", "주황", "꺼짐".
  - `enum LEDMode: String, Codable, CaseIterable, Sendable { case system, off, perState }`. Titles: "macOS 기본", "끄기", "상태별로 정하기".
  - `struct LEDSettings: Codable, Equatable, Sendable { var mode = LEDMode.system; var charging = LEDColor.orange; var paused = LEDColor.green; var heat = LEDColor.orange }`, decoded lossily.
  - `enum MagSafeLEDPolicy { static func target(_ s: LEDSettings, status: MenuBarStatus) -> MagSafeLED? }`:
    - `system` gives nil
    - `off` gives `.off`
    - `perState` maps charging, paused and heatHold to the chosen color's `.led`, and `onBattery` to nil
  - `static func MagSafeLEDPolicy.write(target: MagSafeLED?, last: MagSafeLED?, dirty: Bool) -> MagSafeLED?`:
    - with a target that differs from `last`, it returns the target
    - with no target, `dirty`, and `last != .system`, it returns `.system`
    - otherwise it returns nil
- AppModel:
  - It keeps `lastLED: MagSafeLED?` in memory and `UserDefaults` key `vb.led.dirty`. The key is true after any non-system write and false after a `.system` write.
  - It applies the policy on every `refresh()` and on settings changes. When it is due, it writes through the helper.
  - It skips the write when `!chargeConflicts.isEmpty` or `helperStatus != .ready`.
  - On a write error it shows the message once per error text.
  - At launch, if dirty and the mode is `system`, it writes `.system` once.
  - `didWake` sets `lastLED = nil`.
  - The `willTerminate` handler writes `.system` when dirty.
- Settings card "MagSafe LED":
  - a mode `Picker`; for `perState`, three color pickers ("충전 중", "상한에서 멈춤 또는 완충", "과열로 충전 보류")
  - the caption "MagSafe 케이블로 연결했을 때만 켜집니다. USB-C 단자로 충전하면 효과가 없습니다."
  - When the helper is not `.ready`, the controls are disabled and the reason is shown.

- [ ] Step 1: write the tests:
  - `systemTargetsNothing`, `offTargetsOff`
  - `perStateMapsColors`: defaults give charging `.orange`, paused `.green`, heatHold `.orange` and onBattery nil
  - `sameStateWritesNothing`: `write(target:.green, last:.green, dirty:true) == nil`
  - `changedStateWrites`: `write(target:.orange, last:.green, dirty:true) == .orange`
  - `dirtyFlagResetsOnceOnLaunch`: `write(target:nil, last:nil, dirty:true) == .system`, then `write(target:nil, last:.system, dirty:false) == nil`
  - `cleanSystemWritesNothing`: `write(target:nil, last:nil, dirty:false) == nil`
  - `oldPreferencesGetSystemLED`: preferences JSON without `led` gives `led.mode == .system`
- [ ] Step 2: run `swift test --filter MagSafeLEDTests`. Expected: it fails to compile.
- [ ] Step 3: implement.
- [ ] Step 4: run `swift test`. Expected: all pass.
- [ ] Step 5: build and install. With the user, MagSafe connected:
  - "상태별로 정하기" shows orange while charging and green when paused at the limit
  - "끄기" turns it off
  - quitting the app returns the LED to macOS control
  - set "끄기", `kill -9` the app, then relaunch. Expected: the LED stays off, because the mode is still "끄기". Then choose "macOS 기본". Expected: the LED returns. (The crash-cleanup path for the "macOS 기본" mode is covered by `dirtyFlagResetsOnceOnLaunch`.)
- [ ] Step 6: commit `feat: control the MagSafe LED per charging state`.

### Task 8: Docs, validation and PR

- [ ] Update `docs/COMPATIBILITY.md`:
  - rows for status icon, menu window, power flow, hardware percentage, Low Power Mode and MagSafe LED, with the Task 3 gate result, including whether the LED value survives a reboot (ask the user to reboot once if Task 7 shipped)
  - the helper row: its new requests and protocol version 2
  - the "SMC writes" statement: `ACLC` only
- [ ] Add a `docs/VALIDATION.md` section "Pro features (2026-10-2x)": the test count and the on-device checks from Tasks 3–7.
- [ ] Update `README.md`:
  - features, including the free equivalents of AlDente Pro
  - the helper section: what it can do now, and that existing users must rerun `install-helper.sh`
- [ ] Run `swift test` and `scripts/build-app.sh`. Expected: both pass.
- [ ] Commit `docs: record Pro feature validation`.
- [ ] Push `feat/pro-features` and open a PR to `main`. Check that CI passes.
