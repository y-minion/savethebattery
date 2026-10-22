# Automation (schedules, CLI charge control) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Charge schedules with catch-up, `vbctl charge set|off|topup|end` routed through the running app, and a 충전 page that explains every limit change.

**Architecture:** Pure schedule logic and request parsing live in `BatteryCore`. The schedule runner, the write log extensions and a same-user Unix-socket control channel live in `BatteryPlatform`. The running app is the only writer of charge settings. It calls `ChargeController.apply` for the UI, schedules and CLI requests, and records the source of each write.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`swift test`, Xcode 27.1 toolchain), Darwin sockets.

**Spec:** `docs/superpowers/specs/2026-10-22-automation-design.md`

**Progress:** Tasks 1–8 complete (2026-10-23).

**Out of this plan:** Shortcuts App Intents (spec goal 3). They need the Xcode project from sub-project 3-1, which does not exist yet. The spec allows deferring them ("Xcode 전환이 늦어지면 이 항목만 뒤로 미루고 나머지는 먼저 낸다").

## Global Constraints

- No SMC writes. Every write is blocked while another charge manager is present, and every write is read back.
- Only the running app writes charge settings. `vbctl charge status` still reads without the app.
- Schedule, CLI and Shortcut writes are user writes (`byUser:true`) and log their own source.
- Catch-up window is 12 hours. Only the most recent missed occurrence runs.
- At most 10 rules. A rule needs at least one weekday. Its time is local `hour:minute`. Its action is `setLimit(50…100, step 5)`, `topUp` or `clearLimit`.
- Same-time rules: the one later in the list wins.
- A new or re-enabled rule counts only occurrences after `activeSince`.
- CLI exit codes: 0 success, 1 apply failed or response timed out, 2 usage, 3 app not running or connect failed.
- Channel timeouts: connect and send within 5 s, response within 15 s. Commands accepted: `setLimit`, `clearLimit`, `startTopUp`, `endTopUp` only. Same UID only. Socket file mode 0600.
- All UI text is Korean plain language. No "MCL", "PowerUI" or "topoff" on screen.
- Notifications: 일정 실행 실패 is on by default, 일정 실행됨 is off by default.
- No personal device values in Git.

## Review Focus

1. A slow apply (helper plus 4 s read-back) during a schedule check must not run the same occurrence twice. `lastCheck` is saved before applying (Task 3: `lastCheckIsSavedBeforeApplying`).
2. Editing a rule's time to earlier today must not fire it immediately. Editing resets `activeSince` (Task 1: `editedRuleDoesNotFireForPastTimeToday`).
3. A socket file left by a crashed app must not block the next launch. The server removes it at start (Task 4: `serverReplacesStaleSocket`).
4. A CLI request blocked by another charge manager returns exit 1 with the conflict message, not 3 (Task 5: `blockedRequestMapsToFailureExit`).
5. A time-zone change between checks still runs at most one occurrence (Task 1: `timeZoneChangeRunsAtMostOnce`).

---

### Task 1: Schedule model and policy

**Files:**
- Create: `Sources/BatteryCore/ChargeSchedule.swift`
- Modify: `Sources/BatteryCore/UserPreferences.swift` (add `schedules`)
- Test: `Tests/BatteryCoreTests/ChargeScheduleTests.swift`

**Interfaces:**
- Produces:
  - `enum ScheduleAction: Codable, Equatable, Sendable { case setLimit(Int), topUp, clearLimit; var command: ChargeCommand }`. `topUp` maps to `.startTopUp`.
  - `struct ChargeScheduleRule: Codable, Equatable, Identifiable, Sendable { id: UUID; name: String; weekdays: Set<Int> /* Calendar weekday 1=Sun…7=Sat */; hour: Int; minute: Int; action: ScheduleAction; enabled: Bool; activeSince: Date; var isValid: Bool; mutating func edited(now: Date) }`. `edited` sets `activeSince=now`.
  - `static func templates(now: Date) -> [ChargeScheduleRule]`, which returns, in order:
    - "밤에는 70%": every day 22:00, `setLimit(70)`
    - "평일 아침 완충": weekdays 2…6 at 07:00, `topUp`
    - "주말엔 80%": 1 and 7 at 00:00, `setLimit(80)`
  - `struct ScheduleOccurrence: Equatable, Sendable { rule: ChargeScheduleRule; at: Date }`
  - `enum ScheduleDecision: Equatable, Sendable { case none, run(ScheduleOccurrence), skip(ScheduleOccurrence) }`
  - `enum SchedulePolicy { static let catchUpWindow: TimeInterval = 43_200; static let maxRules = 10; static func next(_ r: ChargeScheduleRule, after: Date, calendar: Calendar) -> Date?; static func nextAny(_ rules: [ChargeScheduleRule], after: Date, calendar: Calendar) -> ScheduleOccurrence?; static func due(_ rules: [ChargeScheduleRule], lastCheck: Date?, now: Date, calendar: Calendar) -> ScheduleDecision }`
  - `enum ScheduleText { static func sentence(_ r: ChargeScheduleRule) -> String; static func days(_ d: Set<Int>) -> String; static func action(_ a: ScheduleAction) -> String }`
  - `UserPreferences.schedules: [ChargeScheduleRule]`. Each element is decoded on its own (a bad element is dropped). `validate()` drops invalid rules and keeps the first 10.

`due` behavior:
- Returns `.none` when `lastCheck` is nil or in the future, or when nothing is due.
- Otherwise it gathers every enabled rule's occurrences in `(max(lastCheck, activeSince), now]` and takes the latest. On a tie, the later index in the list wins.
- Returns `.skip` if that occurrence is older than `now - catchUpWindow`, otherwise `.run`.
- Use `calendar.nextDate(after:matching:DateComponents(hour:minute:weekday:),matchingPolicy:.nextTime)` and walk forward per weekday.

- [ ] **Step 1: Write failing tests** in `ChargeScheduleTests.swift`. Use a fixed `Calendar(identifier:.gregorian)` with time zone `Asia/Seoul`, unless a test sets another zone.
  - `nextOccurrenceRespectsWeekdays`: a weekdays 2…6 07:00 rule, after Friday 08:00 → Monday 07:00.
  - `weekBoundary`: an every-day 00:00 rule. `due(lastCheck: Sun 23:59, now: Mon 00:00:30)` → `.run` at Mon 00:00.
  - `latestOfManyWins`: rules at 21:00 and 22:00. `lastCheck` 20:00, `now` 23:00 → `.run` of the 22:00 rule.
  - `sameTimeLaterInListWins`: two 22:00 rules → the second.
  - `catchUpWindowBoundary`: an occurrence 11 h 59 m before `now` → `.run`; 12 h 1 m before → `.skip`.
  - `firstCheckIsBaseline`: `lastCheck: nil` → `.none`.
  - `clockBackwardsRunsNothing`: `lastCheck` after `now` → `.none`.
  - `disabledRuleIgnored`.
  - `activeSinceLimitsCatchUp`: a rule at 22:00 with `activeSince` 22:30. `lastCheck` 21:00, `now` 23:00 → `.none`.
  - `editedRuleDoesNotFireForPastTimeToday`: a rule edited at 15:00 to 09:00. `lastCheck` 14:59:40, `now` 15:00:10 → `.none`.
  - `dstSpringForwardRunsOnce`: `America/New_York`, a rule at 02:30 on 2026-03-08. `lastCheck` 01:00, `now` 04:00 → exactly one `.run`. A second `due` with `lastCheck` = that `now` → `.none`.
  - `timeZoneChangeRunsAtMostOnce`: `lastCheck` computed in Seoul. `now` 30 min later with a `Europe/London` calendar → at most one occurrence.
  - `sentenceReadsPlainly`: weekdays 2…6, 22:00, `setLimit(70)` → `"평일 22:00 · 상한 70%"`. Every day → `"매일"`, {1,7} → `"주말"`, others → for example `"월·수·금"`. `topUp` → `"한 번 완충"`, `clearLimit` → `"상한 끄기"`.
  - `preferencesDropBadRulesKeepOthers`: JSON with one rule with empty weekdays and one valid rule → after `validate()`, 1 rule. 12 valid rules → 10.
  - `templatesAreValid`: all 3 are `isValid` and have the names above.
- [ ] **Step 2: Run** `swift test --filter ChargeScheduleTests`. Expected: FAIL, the types are not defined.
- [ ] **Step 3: Implement** the interfaces above.
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: decide charge schedules with bounded catch-up`

### Task 2: Write sources, schedule-aware apply, change reasons

**Files:**
- Modify: `Sources/BatteryPlatform/ChargeController.swift`
- Modify: `Sources/BatteryPlatform/ChargeLimitClient.swift` (`ChargeText`)
- Test: `Tests/BatteryCoreTests/ChargeControllerTests.swift`

**Interfaces:**
- Consumes: the existing `apply(_:byUser:source:)`, `ChargeWrite`, `ChargeRecord.log`.
- Produces:
  - `ChargeWrite.Source` gains `schedule`, `cli`, `shortcut`.
  - `ChargeWrite.detail: String?` holds the schedule name. Decoding is tolerant, so old logs load.
  - `apply(_ c: ChargeCommand, byUser: Bool = true, source: ChargeWrite.Source? = nil, detail: String? = nil)`
  - When `c` is `.setLimit` or `.clearLimit`, `byUser` is true, and `record.topUpRequested != nil`: first `write(.endTopUp)`, logged with the same source. If that fails, return its failure. Then apply `c`.
  - `ChargeRecord.lastChange: ChargeWrite?`, the latest `ok` entry.
  - `ChargeText.reason(_ w: ChargeWrite, now: Date, calendar: Calendar) -> String`. Format: `"<HH:mm> <cause>"`, with "어제 HH:mm" or "M월 d일 HH:mm" when not today. Causes by source:

| Source | Cause text |
|---|---|
| `.user` | `직접 바꿈` |
| `.schedule` | `일정 '<detail>'로 바뀜` |
| `.cli` | `명령줄로 바뀜` |
| `.shortcut` | `단축어로 바뀜` |
| `.heat` | `과열 보류로 바뀜` |
| `.topUp` | `완충 후 원래 상한으로 복원` |
| `.quit` | `앱 종료 시 복원` |

- [ ] **Step 1: Write failing tests**
  - `scheduleWriteIsLoggedWithNameAndCountsAsWrite`: `apply(.setLimit(70),source:.schedule,detail:"밤에는 70%")` → `log.last` has source `.schedule`, detail "밤에는 70%"; `writes` increased by 1; `lastWritten==70`.
  - `limitDuringTopUpEndsTopUpFirst`: `enableTo=80`. Start a top-up and observe limit 100. Then `apply(.setLimit(75),source:.schedule)` → success at 75; the log shows `endTopUp` then `setLimit(75)`; `topUpRequested==nil`.
  - `scheduleDuringHeatHoldReplacesHold`: use the `holding` helper, then `apply(.setLimit(85),source:.schedule)` → `record.heat==HeatState()` and `heatPaused==false`.
  - `oldLogWithoutDetailLoads`: decode `{"log":[{"date":0,"command":"clearLimit","source":"user","ok":true}]}` → 1 entry with `detail==nil`.
  - `reasonTextBySource`: assert each of the 7 cause strings above at a fixed `now`, plus the "어제" form.
- [ ] **Step 2: Run** `swift test --filter ChargeControllerTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: log write sources and explain the last limit change`

### Task 3: Schedule runner and store

**Files:**
- Create: `Sources/BatteryPlatform/ScheduleStore.swift`
- Modify: `Sources/BatteryPlatform/SessionStore.swift` (`AppPaths.schedule`)
- Test: `Tests/BatteryCoreTests/ScheduleRunnerTests.swift`

**Interfaces:**
- Consumes: `SchedulePolicy.due`, `ScheduleAction.command`, `JSONFile`.
- Produces:
  - `struct ScheduleRun: Codable, Equatable { date: Date; ruleName: String; action: String; result: Result; enum Result: Codable, Equatable { case ran, failed(String), skipped } }`
  - `struct ScheduleState: Codable, Equatable { var lastCheck: Date?; var recent: [ScheduleRun] }`. `recent` keeps the newest 10.
  - `AppPaths.schedule` = `schedule.json`
  - `final class ScheduleRunner { init(file: JSONFile<ScheduleState>, apply: @escaping (ChargeCommand, ChargeScheduleRule) -> String? /* nil = success, else failure message */); var state: ScheduleState { get }; func check(_ rules: [ChargeScheduleRule], now: Date, calendar: Calendar) -> ScheduleRun? }`

`check` behavior:
- If `lastCheck` is in the future, it is reset to `now`.
- The new `lastCheck=now` is saved **before** `apply` runs.
- Each run or skip is recorded.
- It returns the run, or nil when nothing happened.

- [ ] **Step 1: Write failing tests**
  - `firstCheckOnlySetsBaseline`
  - `dueRuleRunsOnceAcrossChecks`
  - `skippedOccurrenceIsRecorded`
  - `failureMessageIsRecorded`
  - `recentKeepsTen`
  - `lastCheckIsSavedBeforeApplying`: the `apply` closure reads the file and sees the new `lastCheck`.
  - `stateSurvivesRestart`: a new runner on the same file has the same `lastCheck`.
  - `fileIsPrivate`: mode 0600.
- [ ] **Step 2: Run** `swift test --filter ScheduleRunnerTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: run due charge schedules once and keep recent runs`

### Task 4: Control protocol and same-user socket channel

**Files:**
- Create: `Sources/BatteryCore/ControlProtocol.swift`
- Create: `Sources/BatteryPlatform/ControlChannel.swift`
- Modify: `Sources/BatteryPlatform/SessionStore.swift` (`AppPaths.controlSocket` = `control.sock`)
- Test: `Tests/BatteryCoreTests/ControlChannelTests.swift`

**Interfaces:**
- Produces (BatteryCore):
  - `struct ControlRequest: Codable, Equatable, Sendable { command: String; value: Int?; func chargeCommand() -> ChargeCommand? }`. It accepts only `setLimit` (valid per `ChargeCommand.isValid`), `clearLimit`, `startTopUp` and `endTopUp`.
  - `struct ControlResponse: Codable, Equatable, Sendable { ok: Bool; message: String; state: ChargeLimitState? }`
- Produces (BatteryPlatform):
  - `final class ControlServer { init(path: URL, handler: @escaping (ChargeCommand) -> ControlResponse); func start() throws; func stop() }`
    - Unlinks any existing file at `path`, binds and chmods 0600.
    - Accepts on a background queue.
    - Rejects peers whose `getpeereid` UID differs from `getuid()`.
    - Reads one `\n`-terminated line, at most 1024 bytes, with a 5 s read timeout.
    - Unknown or invalid requests get `ok:false,"지원하지 않는 요청입니다."` without calling the handler.
    - Calls the handler with `DispatchQueue.main.sync`.
  - `enum ControlClient { enum Failure: Error, Equatable { case notRunning, timedOut }; static func send(_ r: ControlRequest, path: URL, connectTimeout: TimeInterval = 5, responseTimeout: TimeInterval = 15) throws -> ControlResponse }`

- [ ] **Step 1: Write failing tests**
  - Socket paths must be under 104 bytes, so use `/tmp/vb-<short uuid>.sock`.
  - The handler runs on main, so run the server in tests with a handler that does not need main: give `ControlServer` an internal `init(path:handler:queue:)` that tests call with a private queue.
  - Tests:
    - `requestParsing`: `setLimit` 70 ok; 73 nil; 45 nil; `"reboot"` nil; `clearLimit` ok.
    - `roundTripCallsHandler`: send `setLimit 75` → the handler gets `.setLimit(75)`; the response comes back.
    - `unknownCommandRejectedWithoutHandler`
    - `oversizedLineRejected`
    - `missingSocketIsNotRunning`
    - `slowHandlerTimesOut`: handler sleeps 2 s, `responseTimeout` 0.5 → `.timedOut`.
    - `serverReplacesStaleSocket`: create a regular file at the path, then `start()` succeeds.
    - `socketIsPrivate`: mode 0600.
- [ ] **Step 2: Run** `swift test --filter ControlChannelTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** Use `socket(AF_UNIX,SOCK_STREAM)`, `SO_RCVTIMEO`/`SO_SNDTIMEO` for timeouts and a non-blocking connect with `poll` for the connect timeout.
- [ ] **Step 4: Run** `swift test`. Expected: all pass, with no hang longer than about 3 s.
- [ ] **Step 5: Commit** `feat: add a same-user control channel for charge requests`

### Task 5: `vbctl charge` commands and status report

**Files:**
- Create: `Sources/BatteryCore/ChargeCLI.swift`
- Create: `Sources/BatteryPlatform/ChargeStatusReport.swift`
- Modify: `Sources/VibeCLI/Main.swift` (charge branch and usage text)
- Test: `Tests/BatteryCoreTests/ChargeCLITests.swift`

**Interfaces:**
- Consumes: `ControlRequest`, `ControlResponse`, `ControlClient.send`, `ChargeRecord`, `SchedulePolicy.nextAny`, `AppPaths`.
- Produces:
  - `enum ChargeCLI { enum Action: Equatable { case status(json: Bool), request(ControlRequest) }; static func parse(_ args: [String]) -> Result<Action, String> /* args after "charge"; error = usage text */; static func exitCode(_ r: Result<ControlResponse, ControlClient.Failure>) -> Int32 }`
    - Exit codes: `ok` → 0; `ok:false` → 1; `.timedOut` → 1; `.notRunning` → 3. Usage errors exit 2 in `Main`.
  - `struct ChargeStatusReport: Codable { supported, enabled, limit /* existing keys */; origin: String; topUpActive: Bool; nextSchedule: Date? }`
    - `static func make(state:, record: ChargeRecord?, rules: [ChargeScheduleRule], appRunning: Bool, now:, calendar:)`
    - `nextSchedule` is set only when `appRunning`. "Running" means the socket exists and accepts a connection.
  - CLI messages:
    - not running: `"VibeBattery 앱이 실행 중이어야 합니다. 앱을 열고 다시 시도하세요."`
    - timeout: `"결과를 확인하지 못했습니다. vbctl charge status로 확인하세요"`
    - otherwise the response `message`
  - Usage lines:
    ```
    vbctl charge status [--json]
    vbctl charge set <50-100>
    vbctl charge off
    vbctl charge topup
    vbctl charge end
    ```

- [ ] **Step 1: Write failing tests**
  - `parsesEachCommand`: `set 70`, `off`, `topup`, `end`, `status --json`.
  - `rejectsBadInput`: `set 73`, `set 40`, `set abc`, `set` → errors containing `"vbctl charge set <50-100>"`.
  - `exitCodes`
  - `blockedRequestMapsToFailureExit`: `ok:false` with an AlDente conflict message → 1.
  - `statusReportKeepsOldKeys`: the JSON has `supported`/`enabled`/`limit` plus the new keys.
  - `nextScheduleOnlyWhenAppRuns`
- [ ] **Step 2: Run** `swift test --filter ChargeCLITests`. Expected: FAIL.
- [ ] **Step 3: Implement** the types, then wire `Main.swift`: parse, then status (read-only as today, plus the report) or send, then print the message and `exit` with the code.
- [ ] **Step 4: Run** `swift test && swift build && .build/debug/vbctl charge set 70; echo $?` with no app socket in the test environment. Expected: tests pass, then the not-running message and `3`.
- [ ] **Step 5: Commit** `feat: control the charge limit from vbctl through the app`

### Task 6: App wiring (runner, server, notifications)

**Files:**
- Modify: `Sources/VibeBattery/AppModel.swift`
- Modify: `Sources/BatteryCore/NotificationTypes.swift` (`scheduleFailed=true`, `scheduleRan=false`, tolerant decode; `AlertEvent.sections` gains `"charge"`)
- Test: `Tests/BatteryCoreTests/NotificationSettingsTests.swift`

**Interfaces:**
- Consumes: `ScheduleRunner`, `ControlServer`, `ChargeController.apply(_:byUser:source:detail:)`, `ChargeText.reason`.
- Produces (AppModel, used by Task 7):
  - `scheduleRuns: [ScheduleRun]`
  - `nextSchedule: ScheduleOccurrence?`
  - `lastChangeText: String?`
  - `func addSchedule(_:)`, `func updateSchedule(_:)` (calls `edited(now:)` when time, days or action changed, or when re-enabled), `func removeSchedule(id:)`
  - `func applyCharge(_:)` stays for the UI and logs source `.user`.

Wiring:
- `refresh` and `didWake` call `runner.check(preferences.schedules, now:Date(), calendar:.current)` after `refreshCharge`.
- The runner's `apply` uses `chargeController.apply(cmd,source:.schedule,detail:rule.name)` and refreshes `charge`. It never sets `message`.
- On a failed run, deliver `AlertEvent(id:"schedule.failed",title:"일정 '<name>' 실행 실패",body:<message>,section:"charge",thread:"charge")` when `scheduleFailed` is on.
- On a successful run, deliver `"일정 '<name>' 실행됨"` when `scheduleRan` is on.
- `init` starts `ControlServer(path:AppPaths.controlSocket)`. Its handler calls `chargeController.apply(cmd,source:.cli)` and returns `ok`, the message (same text as `applyCharge`) and the state.
- `willTerminate` stops the server.

- [ ] **Step 1: Write failing tests**
  - `scheduleNotificationDefaults`: `scheduleFailed==true`, `scheduleRan==false`, and an old JSON without these keys loads the defaults.
  - `chargeSectionRoutes`: `AlertEvent.route("charge")=="charge"`.
- [ ] **Step 2: Run** `swift test --filter NotificationSettingsTests`. Expected: FAIL.
- [ ] **Step 3: Implement** the settings, then the AppModel wiring.
- [ ] **Step 4: Run** `swift test && scripts/build-app.sh | tail -1`. Expected: pass, then the bundle path.
- [ ] **Step 5: Commit** `feat: run schedules and serve vbctl requests from the app`

### Task 7: 충전 page, dashboard summary, menu, settings

**Files:**
- Create: `Sources/VibeBattery/ChargeView.swift` (page, schedule list, editor sheet, recent runs, helper and log disclosure)
- Modify: `Sources/VibeBattery/App.swift` (sidebar order and `case "charge"`; menu lines and buttons)
- Modify: `Sources/VibeBattery/DashboardView.swift` (replace `ChargeControlCard()` with a summary card)
- Modify: `Sources/VibeBattery/SettingsView.swift` (move the heat card out; add "명령줄과 단축어"; add two schedule notification toggles)
- Modify: `Sources/VibeBattery/ChargeControlView.swift` (show `lastChangeText` under the limit)

**Interfaces:** consumes Task 6's AppModel members, `ScheduleText`, `ChargeScheduleRule.templates`, `SchedulePolicy.nextAny`.

Content follows the spec's "화면 구성 원칙", "사이드바", "충전 페이지" and "메뉴 막대" sections exactly. Pinned values:

- **Sidebar:** 대시보드, 충전 (`bolt.batteryblock`), 건강 분석, 바이브 코딩, 앱과 프로세스, 설정.
- **Empty schedule state:** the 3 templates as one-tap buttons.
- **Rule row:** `ScheduleText.sentence`, an enable toggle and `"다음: 오늘 22:00"`. Use "내일" or "M월 d일" when not today.
- **Editor sheet:**
  - quick chips 매일/평일/주말 plus 7 day chips
  - `DatePicker` for hour and minute
  - action picker: 상한 N% with a stepper (50…100 step 5, 80% marked "권장"), 한 번 완충, 상한 끄기
  - a name field, auto-filled from `ScheduleText.sentence` until edited
  - a warning `"같은 시각에 다른 일정이 있어요. 목록에서 아래쪽 일정이 적용됩니다."` when the time collides
  - save disabled when no day is selected or there are already 10 rules
- **"최근 실행" disclosure:** collapsed, 10 rows of date, name, result.
- **Footer copy:** `"앱이 실행 중일 때 동작합니다. 맥이 잠들어 놓친 일정은 12시간 안이면 깨어날 때 실행합니다."`
- **"헬퍼와 기록" disclosure:** collapsed; the helper text plus the last 20 writes as reason lines.
- **Dashboard card:** current limit, `lastChangeText`, next schedule and a "충전 관리 열기" button. No write controls.
- **Menu:**
  - line `"상한 70% · 다음 일정 22:00"`
  - button "한 번 100% 충전", or "완충 종료" while a top-up is active
- **Settings card "명령줄과 단축어":**
  - a "vbctl 경로 복사" button (`Bundle.main.bundleURL` + `/Contents/MacOS/vbctl`)
  - 3 example lines (`vbctl charge set 70`, `vbctl charge topup`, `vbctl charge status --json`)
  - `"단축어 앱의 '셸 스크립트 실행'에 위 명령을 넣어 쓸 수 있습니다."`

- [ ] **Step 1: Build check** `scripts/build-app.sh | tail -1`. Expected: the bundle path, with no warnings from the new files (`swift build 2>&1 | grep -c warning:` unchanged from before the task).
- [ ] **Step 2: Run** `swift test`. Expected: all pass.
- [ ] **Step 3: Commit** `feat: add the charge page with schedules and change reasons`

### Task 8: Docs, on-device check, publish

**Files:**
- Modify:
  - `README.md` (feature bullets, `vbctl charge` usage)
  - `docs/COMPATIBILITY.md` (Schedules / Shortcuts row: schedules and CLI implemented, App Intents pending 3-1)
  - `docs/VALIDATION.md` (Automation section)

- [ ] **Step 1: Verify** `swift test 2>&1 | tail -1; scripts/build-app.sh | tail -1; python3 scripts/smoke-sessions.py .build/debug/vbctl | tail -1`. Expected: all pass.
- [ ] **Step 2: Install** — quit the app, copy it with `ditto --norsrc --noextattr dist/VibeBattery.app /Applications/VibeBattery.app`, then relaunch. Then check on the device:
  - `/Applications/VibeBattery.app/Contents/MacOS/vbctl charge set 75; echo $?` → 0. The 충전 page shows "명령줄로 바뀜".
  - Quit the app, then `vbctl charge set 75; echo $?` → 3.
  - Relaunch and make a rule 1–2 minutes ahead. Within about 30 s of that time the limit changes, and "최근 실행" shows it.
  - The user looks at the 충전 page, the templates, the editor, the dashboard card and the menu.
  - Restore the user's limit (70%).
  Record the results in `VALIDATION.md`.
- [ ] **Step 3: Commit and push** `docs: record automation validation`. Then `git push -u origin feat/automation` and open a PR to `main`. Wait for CI to pass.
