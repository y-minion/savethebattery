# Validation — development preview 0.1

Validated on the initial M4 Pro / macOS 27.0.1 target and a GitHub macOS runner.

- 17 Swift Testing tests cover sensor decoding, charging decision policies, ownership guards, settings, history, and inactive-session retention. Charging policies are pure models; this does not validate hardware charging writes.
- Disposable-process integration checks cover literal arguments, exit codes, expiry before completion, release without command cancellation, cancellation of a signal-ignoring child, concurrent power assertions, registered resource cleanup, failed-session preservation, and `--keep`.
- Power-assertion checks inspect the operating system's assertion list for the two test supervisor PIDs. Releasing one leaves the other intact.
- The same integration suite runs against the CLI embedded in the release app, after both executables have been built. Their distinct names (`Save the Battery` and `stb`) also work on case-insensitive filesystems.
- An interactive pseudo-terminal check confirmed that input reaches the wrapped command and the resulting exit status is preserved.
- The native dashboard, process list, session controls, and settings were inspected. Live readings and the embedded CLI were checked on the target Mac.
- The bundle is locally ad-hoc signed; the build also creates an archive without Finder presentation metadata.

The independent review found PID-reuse risk in arbitrary raw signals, delayed assertion release after cancellation, and expiry/completion ordering. Raw signals now target only unreaped direct children; selected ordinary apps use AppKit application-instance termination. Cancellation releases the lease immediately, and expiry/release is processed before successful completion. Regression checks reproduce the original signal-ownership and expiry failures and pass with the fixes.

## Charge control (2026-10-20)

- 55 Swift Testing tests now pass, adding charge-command ranges, limit origin, read-back matching, heat-hold hysteresis (5-minute stable resume, stale and missing temperature, low charge, missing helper, external change during a hold), 5% limit steps, conflict detection (including a leftover AlDente daemon and excluding Save the Battery's own helper), controller routing and read-back failure, persistence across restarts, pausing after a failed automatic write or an external change, keeping the hold when a restore fails, refusing top-up during a hold, restoring on app quit, keeping the original owner of a restored limit, top-up lifecycle, helper status reasons, detection of battery and Battery Toolkit, legacy preference files, and helper client authorization.
- The PowerUI bridge rejects out-of-range limits before calling macOS; tests never pass a valid limit, so automated runs do not change the real charge limit.
- On the target Mac, `stb charge status` reported the same limit as `pmset -g battlimit` (79%) and detected the running AlDente; the rebuilt app launched with writes blocked and left the limit unchanged.
- The release bundle embeds `STBChargeHelper` signed with identifier `io.github.y-minion.savethebattery.helper` and the install/uninstall scripts; both scripts refuse to run without root.
- Hardware validation: see "On-device validation (2026-10-21/22)" below.

## Health insights (2026-10-20)

- Swift Testing now runs 100 tests in 16 suites, adding precise health and hashed battery identity decoding (legacy history still loads), BU-808 table reproduction, monotonicity and clamping of the stress model, time-weighted daily accumulation (five-minute gap, local-midnight split, clock going backwards, missing sensors, 400-day retention), battery replacement segments, Theil–Sen trend gating, exact and outlier-robust projections, nearly flat declines beyond the 15-year horizon, cycle projections, sleep drain rules, suggestion thresholds, report windows, Korean text, corrupt-file recovery, private file permissions, five-minute save throttling and sleep-record limits. After the final review: loading files with missing keys, keeping every corrupt copy, read-only CLI loads, explaining which trend condition is missing, ignoring integer rounding in sleep drain, counting heat on the adapter for the heat-hold suggestion, surviving a forward clock jump, caching the trend fit, and keeping the battery identifier out of snapshot JSON.
- App Nap check: in the running app's own history, refresh gaps stretched to at most 120 s and every gap over 300 s contained a system sleep, so the five-minute unknown-gap rule is not hiding awake time.
- On the target Mac, `stb health` and `stb health --json` ran from the release bundle against an empty scratch data directory and exited 0; a release build launched with a scratch data directory and wrote a private `health.json` on its first refresh. The user's running instance and data were not touched. The screen could not be captured remotely, so the health screen layout has not been visually inspected.
- Pending: a month of real records before the trend projection can be checked against the device.

## Notifications (2026-10-20)

- Swift Testing now runs 143 tests in 23 suites, adding notification defaults and tolerant decoding, threshold validation, click-target allow-listing, heat-step mapping, limit reached only after an observed charging step (with gaps as fresh baselines, heat hold and top-up excluded, re-arming after a five-minute unplug or a new limit), top-up done once per request, low battery re-arming after a 5-point rise or two minutes on the adapter, limit changes only when Save the Battery did not write them (its own writes, restores, top-up and a yielded hold excluded), loss of charge control, temperature thresholds with a 3 °C re-arm and 30-minute cooldown (+2 °C on battery, stale, missing and battery-less readings ignored), conflicts by name, a stuck heat hold repeated daily, paused/failed hold, a missing sensor after ten minutes, session endings by end time and exit code (including after a released protection), adapter or expiry releases but not user releases, cancelled sessions, late sessions within ten minutes, batching over three, pruning, sleep drain, weekly suggestions, the weekly summary keyed by ISO week after Monday 09:00, disabled events advancing memory, future timestamps expiring, and private change-only memory writes with corrupt-file recovery. After the final review: Save the Battery's own heat-hold restore is never reported as an outside limit change (every charge write is counted), an unconfirmed top-up stops muting limit alerts after 24 hours, endings that happened while the app was closed are not announced on relaunch, and a paused heat hold is announced even with the app in front.
- A release build launched with a scratch data directory stayed running for 40 s without requesting notification permission and wrote `notify.json` with mode 0600; the debug binary run outside an `.app` bundle also stayed running (no UserNotifications use). The running app and its data were not touched.
- On-device checks: see "On-device validation (2026-10-21/22)" below.

## On-device validation (2026-10-21/22)

With the user at the target Mac after AlDente and its helper were removed (its sub-80 limit did not persist; the limit was off afterwards).

| Check | Result |
|---|---|
| Helper install | Pass after copying the app with `ditto --norsrc --noextattr`. The first attempt failed the strict signature check because an iCloud-synced checkout re-adds Finder metadata; the build now signs in a temporary folder |
| 85% (PowerUI) | Pass; app, `stb` and `pmset` agree |
| 75% / 70% (helper) | Fail, then pass. macOS applies helper writes a moment after the notification, so the immediate read-back saw the old value; read-back now polls up to 4 s |
| 70% from the off state | Fail, then pass. "Off" is stored as `MCLFeatureState = 0` and "on" as `1` (integer); the helper now writes 1 when the state is 0 or missing and leaves any other value alone |
| One-time full charge | Charging resumed within a minute. PowerUI reports the top-up as enabled at 100% (not disabled), so the app first missed it and hid "완충 종료"; fixed. Ending it re-enabled the limit at macOS's stored 80% instead of 70%; the app now re-applies its last limit, observed as `setLimit(70)` one second after the user's end request |
| Persistence | Limit kept after app quit, sleep/wake and a reboot; the login item started the app and the helper ran at boot |
| Notifications | Permission prompt, test alert with the app in front and behind, click opens the window, permission kept across rebuilds, full-charge alert at 99%. Permission granted in System Settings now refreshes the settings card without a relaunch |
| Screens | Health analysis screen and notification settings card inspected by the user |

- Unexplained once: during the first full charge the limit turned off and the app's record matched a successful "turn off" that the user did not press; heat hold was off and the system log had no trace. Every attempted charge write is now logged with its source; it has not recurred.
- Not yet observed on the device: macOS ending a top-up by itself, real high-temperature heat hold, and the remaining notification events.
- Swift Testing now runs 152 tests in 23 suites.

## Automation (2026-10-23)

- Swift Testing runs 206 tests in 27 suites. New tests cover:
  - schedule next/due rules: weekdays, week boundary, latest of many, same-time order, 12-hour catch-up boundary, first-check baseline, clock going backwards, disabled and newly edited rules, DST spring-forward and fall-back, time-zone change
  - Korean schedule text and lossy preference decoding
  - write sources and the change reason, including a limit changed elsewhere afterwards
  - top-up ended before a chosen limit, refusing `end` with no top-up
  - the schedule runner saving its last check before applying
  - the control channel: request allow-list, round trip, oversize line, missing socket, response timeout, stale socket, 0600 mode, and a client that hangs up
  - CLI parsing and exit codes, and the status report
- On the target Mac (limit kept at 70% throughout, writing the same value):
  - `stb charge set 70` → exit 0, logged as the command line
  - with the app quit → exit 3, and the socket was removed
  - `set 73` → exit 2
  - `end` with no top-up → exit 1
  - A schedule two minutes ahead ran within 30 s and was logged as a schedule write
  - The user checked the charge page, the schedule editor, the dashboard card and the menu
- Found on the device and fixed:
  - the app quit silently (SIGPIPE) after `stb charge status` checked whether it was running
  - successful schedules were listed as failed because of an optional fallback in the app

Not claimed as validated: real high-temperature heat hold, physical display behavior across external monitors, lid-close/background automation compatibility, manual termination of the user's apps, or support across other hardware/OS combinations. See [the capability report](COMPATIBILITY.md) for unimplemented features.

## Xcode build and Shortcuts (2026-10-24)

- The app is built from `SaveTheBattery.xcodeproj` (generated by XcodeGen from `project.yml`); the Swift package still runs the tests. Swift Testing runs 209 tests in 28 suites, adding the Shortcuts status summary (mapping, limit off, no battery).
- The release bundle contains `Metadata.appintents`, `stb`, `STBChargeHelper` (identifier `io.github.y-minion.savethebattery.helper`) and both helper scripts, passes `codesign --verify --strict`, and the embedded `stb` passes the session smoke test. CI (macos-15 runner, ad-hoc signing) builds the same script.
- Shortcuts showed no actions for the ad-hoc build. Signed with an Apple Development identity, the installed app listed all five actions.
- On the target Mac: "배터리 상태 가져오기" returned the summary; "충전 상한 설정" 80 then 70, "한 번 완충 시작" and "완충 종료" all succeeded and were logged with the Shortcuts source; the user saw them in the dashboard history. The helper kept answering the team-signed app (70% is below the PowerUI range).

## Pro features (2026-10-25)

- Swift Testing runs 238 tests in 33 suites (`swift test --disable-xctest`), including the new status icon, menu, power flow, Low Power Mode and MagSafe LED logic.
- MagSafe LED hardware gate on the target (MagSafe 3, checked by eye): initial read 3; `off` turned the LED off; `system` brought it back (green); `orange` orange; `green` green; `system` restored. Reading `ACLC` returns the displayed colour with about one read of lag and never the control mode, so the app confirms writes by the helper's reply.
- On-device checks, all passed (user):
  - menu window sections and order; quick limit 70; hiding and moving settings cards persists across relaunch
  - dashboard power flow and hardware percentage
  - Low Power Mode switch on/off matches System Settings; System Settings changes are followed; Shortcut on/off works
  - LED: "끄기" turns it off, "상태별로 정하기" shows green while paused at the limit, "macOS 기본" restores, quitting the app restores macOS control
- After a reboot (2026-10-28, mode "macOS 기본", paused at the 70% limit on AC): the app started at login, the dirty flag was clear and the LED was green under macOS control.
- Not checked: whether "끄기" survives a reboot (before login, and after the app relaunches). The LED works only with the MagSafe cable, not USB-C.
- Not included: stop charging while sleeping (by decision); sailing lower bound, forced discharge and calibration (firmware-blocked).

## Free distribution (2026-10-28)

Build facts: Apple's timestamp server accepted the development certificate (`codesign -dvv` shows `Timestamp=` and `TeamIdentifier=JQWWU7443A`); the build is universal (x86_64 arm64).

On-device results (M4 Pro, macOS 27.0.1, 2026-10-29 to 2026-10-31; the user did the clicks):

1. **Install from a clean state.**
   - The installer replaced the running app from a local release (`STB_RELEASE_BASE=file://…`).
   - A browser-style download passed:
     - the zip with a `com.apple.quarantine` flag, unzipped and dragged to Applications;
     - "Open Anyway" in System Settings;
     - the app ran with the approved quarantine flag (`01c3`).
   - The one-liner against a real GitHub release can only be checked after the first release.
2. **Language.** In English, the UI, notifications, Shortcuts and `stb` passed. In Korean, Shortcuts passed after the rename.
3. **Helper pinning.**
   - Reinstalling from the in-app button showed a confirmation.
   - An ad-hoc copy was refused by the team-pinned helper (exit 1).
   - The official build set 70%, switched Low Power Mode and set the LED.
4. **Version notice and update.** "Update now" ran against a local feed (`STB_RELEASE_FEED`) with a team-signed 0.2.1 build. The app:
   - downloaded it, verified it and swapped it in;
   - restarted as 0.2.1 with no password and no Gatekeeper prompt;
   - left no quarantine flag;
   - had the old copy and temp files removed;
   - kept the helper answering (`stb charge set 70`).

   The GitHub path can only be checked after the first release.
5. **Uninstall.** `uninstall.sh` answered N, then the password, then N. The app, the helper and the LaunchDaemon were gone. History (717 KB) and settings were kept, and the 70% limit stayed in force.

## Rename and easy install (2026-10-30 to 2026-10-31)

- **Rename to Save the Battery** (bundle ID `io.github.y-minion.savethebattery`, CLI `stb`):
  - the data folder was moved to `~/Library/Application Support/savethebattery`;
  - the old helper was removed and the new one installed from the app;
  - CI passed on the renamed branch.
- **Disk image.**
  - **Signed image refused:** a signed but unnotarized image was refused by Gatekeeper when a quarantined copy was opened (`spctl` "rejected", no mount).
  - **Unsigned image mounts:** an unsigned image mounted. Since then, `build-app.sh` leaves the image unsigned and `test-install.sh` checks that it stays so.
  - **No warning shown:** opening the app inside the image showed no warning dialog. "Open Anyway" was in System Settings and worked.
- **Move to Applications:**
  - **From the disk image.** The app ran translocated. The dashboard card (at the top; it was scrolled out of view at first) moved it. Then:
    - the copy in Applications had no quarantine flag;
    - the image was untouched;
    - the translocation mount was gone.

    A launch prompt was added afterwards because the card was easy to miss.
  - **From the build folder.** The launch prompt appeared and moved the app. The original went to the Trash.
- **Set 80% card.** It appeared after "Turn off limit" and set 80% without the helper.
- **Install helper and apply.** After the helper was removed, choosing 70% showed "Install helper and apply". One password installed the helper and applied 70%.
  - The macOS dialog reads "'Save the Battery'이(가) 시작한 스크립트에 대해 관리자 접근 권한을 허용하시겠습니까?". It names the app; the custom `with prompt` text is not shown on this macOS.
- **App icon.** It ships in the asset catalog (`AppIcon.icns`, `Assets.car`).
