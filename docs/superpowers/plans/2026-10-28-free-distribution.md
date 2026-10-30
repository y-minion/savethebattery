# Free Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship VibeBattery 0.2.0 free on GitHub Releases. The release includes:
- a one-line installer and an uninstaller
- English and Korean UI
- a team-pinned root helper with no paid program
- a daily new-version notice
- honest measured-facts copy
- an open-source storefront: README in two languages, Pages site and launch drafts

**Architecture:**
- **Localization:** one code-based mechanism, `tr(en, ko)` in `BatteryCore`, used by every target. App Intents use `ko.lproj/*.strings` because Shortcuts reads them from the bundle.
- **Helper replies:** they become stable codes (`HelperReply`) that are localized in the app.
- **Requirement strings:** each side builds its XPC requirement at runtime from its own signature's team ID, so official builds pin `JQWWU7443A` and ad-hoc builds stay identifier-only.
- **Scripts:** release, install and uninstall are POSIX `sh`. Pure rules (language, semver, platform gate, requirement strings) live in `BatteryCore` and are unit-tested.

**Tech Stack:** Swift 6.4 toolchain (Swift 5 language mode), SwiftUI, AppIntents, Security.framework (SecCode), URLSession, Swift Testing, Xcode 27.1 / XcodeGen, POSIX sh, GitHub CLI, GitHub Pages Actions.

**Spec:** `docs/superpowers/specs/2026-10-28-free-distribution-design.md`

## Plan rulings against the spec

These are recorded here so reviewers do not flag them.

- **P1. Localization mechanism:** `tr(en, ko)` in code instead of String Catalogs. SwiftPM's CLI build (`swift test`) does not reliably compile `.xcstrings`, and `vbctl` and the root helper have no reliable resource bundle.
  - A two-argument function makes a missing translation impossible at compile time and testable under `swift test`.
  - App Intents titles, parameters and phrases are compile-time `LocalizedStringResource` keys. They use English keys plus `Resources/ko.lproj/Localizable.strings` and `Resources/ko.lproj/AppShortcuts.strings`.
- **P2. Team pinning source:** the team ID is read at runtime from the process's own code signature (`SecCodeCopySelf` → `kSecCodeInfoTeamIdentifier`), not baked in by `build-app.sh`.
  - It has the same effect: official builds carry `JQWWU7443A`, and ad-hoc builds carry none.
  - It needs no build plumbing and cannot drift from the real signature.
- **P3. In-app helper install:** the spec assumes the helper is installed through an admin-password dialog in the app. Today the app only shows a `sudo` command.
  - Task 6 adds the dialog (`do shell script … with administrator privileges`). The terminal command stays as fallback text.

## Global Constraints

- **Paid services:** no paid Apple program, no telemetry, no third-party hosting or scripts. The only network request is `GET https://api.github.com/repos/y-minion/vibebattery/releases/latest`.
- **Competitor names in public copy:** none — README, site, release notes, launch drafts, app UI. The only exceptions are the conflict-safety lists (README safety note; `SettingsView` conflict message), which keep the names AlDente, batt, battery, Battery Toolkit.
- **Claims:** no unmeasurable lifespan claims (no "adds N years/months", no "% longer life"). Stress stays labelled as relative, from Battery University BU-808.
- **Language:**
  - English is the base language and Korean the translation.
  - `AppLanguage.resolve`: an env `VB_LANG` of `ko` or `en` wins; otherwise the first `Locale.preferredLanguages` entry starting with `ko` gives Korean; everything else gives English.
  - `--json` output keys and values are never translated.
- **Hangul literals:** allowed in `Sources/**/*.swift` only inside `tr(…)` calls. They are allowed in `Resources/ko.lproj/*`, `Tests/**`, `docs/**`, `README.ko.md` and `site/ko/**`. In `scripts/*.sh` they are allowed only on lines that call `msg`.
- **Helper:**
  - `HelperPolicy.protocolVersion = 3`. A v2 helper is `.outdated`; it still sets limits, and the app asks for a reinstall with a reason.
  - Its allow-list (`/Applications/VibeBattery.app/`, console user, fixed requests, ACLC 0/1/3/4) is unchanged.
- **Signing identity:**
  - Free "Apple Development" certificate. Team ID = subject OU `JQWWU7443A`. Expires 2027-10-23. Never upload it; never commit `dev.pem`.
  - Release signing adds `--timestamp`. Ad-hoc builds stay possible for CI and self-builders.
- **Charge limiting** is supported only on macOS ≥ 26.4 and arm64. Everything else on macOS ≥ 15.
- **Version and releases:**
  - First public version `0.2.0`, labelled beta in the notes only.
  - Never `gh release create --prerelease`.
  - The version bump lands by PR; `release.sh` never commits or pushes to `main`.
- **Installer:**
  - Installs only to `/Applications`, without sudo. If `/Applications` is not writable, it stops with an admin message.
  - It verifies SHA-256 before touching `/Applications`.
- **Checks:** `swift test --disable-xctest`, `swift build`, `scripts/smoke-sessions.py`, `scripts/build-app.sh` and CI keep passing.
- **Style:** match the surrounding code (compact Swift, few spaces, short doc comments).

## Review Focus

1. **Preferred languages like `en-KR`, `ko-KR`, `zh-Hans`, empty, and a `VB_LANG` override.** Expected: `en-KR` → English, `ko-KR` → Korean, `zh-Hans` → English, empty → English, `VB_LANG=ko` → Korean even with an English system. Pinned in Task 1.
2. **A v2 helper (Korean reply text) talking to the new app.** Expected: unknown reply text is shown as-is; the status is `.outdated`; LED "unsupported" is detected from both the new code and the old v2 Korean sentence. Pinned in Task 2.
3. **Release tags `v0.10.0` vs `v0.9.0`, `0.2.0` vs `v0.2.0`, `v0.3.0-beta.1`, garbage, and an HTTP 403 rate limit.** Expected: numeric comparison, the `v` is optional, a pre-release suffix is ignored for ordering but a same-core pre-release is not newer, garbage gives no notice, and network or HTTP failure is silent. Pinned in Task 7.
4. **`install.sh` with a bad checksum, a running app, an existing install, macOS 14, or unwritable `/Applications`.** Expected: a bad checksum aborts with `/Applications` untouched; a running app is quit; the existing app is replaced through a temp copy; macOS < 15 refuses; unwritable stops with the admin message. Pinned in Task 8.
5. **An ad-hoc app talking to a team-pinned helper, and macOS 26.3, 26.4 and Intel 27.0.**
   - Helper: the requirement strings differ (pinned vs identifier-only), and an ad-hoc app shows a "self-built" note.
   - Platform gate: 26.3 arm64 is unsupported, 26.4 arm64 is supported, x86_64 is unsupported.
   - Pinned in Tasks 2 and 3.

---

### Task 1: Language foundation and shared `BatteryCore`/`BatteryPlatform` text

**Files:**
- Create: `Sources/BatteryCore/Localization.swift`, `Tests/BatteryCoreTests/LocalizationTests.swift`
- Modify (every Hangul literal → `tr`): all files under `Sources/BatteryCore/` and `Sources/BatteryPlatform/` with Hangul, except the `MagSafeLEDText`, `LowPowerText`, `ChargeHelperXPC.noReply` and `ControlChannel` strings, which Task 2 owns as codes
- Modify: existing tests that assert Korean text. Wrap them in `AppLanguage.$forced.withValue(.ko)`, and add one English assertion per text enum.

**Interfaces:**
- Produces:
  - `public enum AppLanguage: String, Sendable, CaseIterable { case en, ko }`
  - `public static func resolve(env: String?, preferred: [String]) -> AppLanguage`
  - `@TaskLocal public static var forced: AppLanguage?`
  - `public static let system: AppLanguage`, which is `resolve(env: ProcessInfo.processInfo.environment["VB_LANG"], preferred: Locale.preferredLanguages)`
  - `public static var current: AppLanguage { forced ?? system }`
  - `public func tr(_ en: String, _ ko: String) -> String`, a free function in BatteryCore that returns by `AppLanguage.current`
  - `public var locale: Locale` on `AppLanguage` (`en_US` / `ko_KR`), used for date formatters

- [ ] **Step 1: Write failing tests in `LocalizationTests.swift`**

```swift
@Test func resolvesLanguage() {
    #expect(AppLanguage.resolve(env: nil, preferred: ["ko-KR","en-US"]) == .ko)
    #expect(AppLanguage.resolve(env: nil, preferred: ["en-KR","ko-KR"]) == .en)
    #expect(AppLanguage.resolve(env: nil, preferred: ["zh-Hans"]) == .en)
    #expect(AppLanguage.resolve(env: nil, preferred: []) == .en)
    #expect(AppLanguage.resolve(env: "ko", preferred: ["en-US"]) == .ko)
    #expect(AppLanguage.resolve(env: "fr", preferred: ["ko"]) == .ko)  // unknown env is ignored
}
@Test func trFollowsForcedLanguage() {
    AppLanguage.$forced.withValue(.ko) { #expect(tr("Off","끄기") == "끄기") }
    AppLanguage.$forced.withValue(.en) { #expect(tr("Off","끄기") == "Off") }
}
@Test func hangulOnlyInsideTr()  // see Step 3
```

- [ ] **Step 2: Run `swift test --disable-xctest --filter LocalizationTests`.** Expected: FAIL (`AppLanguage` not defined).

- [ ] **Step 3: Implement `Localization.swift` and the guard test `hangulOnlyInsideTr`.**
  - **What the test scans:** every `.swift` file under `Sources/`, found from `#filePath` → repo root.
  - **Which lines are allowed:** a line containing a Hangul syllable (U+AC00–U+D7A3) is allowed only if it contains `tr(`, or if it is inside a `"""` multi-line literal whose opening line contains `tr(`. Toggle on each line with an odd count of `"""`.
  - **The shrinking list:** the test has `static let pending: Set<String>` of repo-relative files not yet converted, which it skips. This task starts it with every app-target file plus `Sources/VibeCLI/*`, `Sources/VBChargeHelper/main.swift`, and the files Task 2 owns. Tasks 2, 4, 5 and 6 remove their entries, and Task 6 leaves it empty.
  - **What it reports:** a failure lists `file:line`.

- [ ] **Step 4: Convert every Hangul literal in the files this task owns to `tr("English","원문")`.**
  - Keep the Korean exactly as it is.
  - Write plain, short English in the same tone. Units and numbers keep the same format specifiers.
  - Date formatters in `ChargeLimitClient.stamp` use `AppLanguage.current.locale`. English stamps read "Yesterday 22:00" and "Oct 3 22:00".
  - `HealthReport.month` renders "Oct 2026" in English and "2026년 10월" in Korean.
  - `Suggestion.message` is localized when the suggestion is built.

- [ ] **Step 5: Run `swift test --disable-xctest`.** Expected: all pass, including the updated Korean assertions under `.ko` and the new English ones.

- [ ] **Step 6: Commit** — `feat: add English and Korean text for shared battery logic`

### Task 2: Helper reply codes, protocol 3 and team pinning

**Files:**
- Create: `Sources/BatteryCore/HelperReply.swift`, `Sources/BatteryPlatform/CodeSigningIdentity.swift`, `Tests/BatteryCoreTests/HelperV3Tests.swift`
- Modify:
  - `Sources/BatteryCore/HelperPolicy.swift`
  - `Sources/BatteryCore/MagSafeLEDPolicy.swift` (`MagSafeLEDText`, `outcome(reply:)`)
  - `Sources/BatteryCore/LowPowerSettings.swift` (`LowPowerText`)
  - `Sources/BatteryPlatform/ChargeHelperXPC.swift`, `Sources/BatteryPlatform/ControlChannel.swift`
  - `Sources/VBChargeHelper/main.swift`
  - the remove-from-`pending` entries in `LocalizationTests`

**Interfaces:**
- Consumes: `tr`, `AppLanguage` (Task 1).
- Produces:
  - `public enum HelperReply: String, CaseIterable, Sendable`, with cases:
    - `limitOutOfRange = "limit.outOfRange"`
    - `limitSaveFailed = "limit.saveFailed"`
    - `lowPowerReadFailed = "lowPower.readFailed"`
    - `lowPowerMissing = "lowPower.missing"`
    - `lowPowerFailed = "lowPower.failed"`
    - `ledValueRejected = "led.valueRejected"`
    - `ledUnsupported = "led.unsupported"`
    - `ledFailed = "led.failed"`
    - `noReply = "xpc.noReply"`
    - `unsupportedRequest = "control.unsupported"`
  - `public var text: String`, localized with `tr`
  - `public static func display(_ wire: String?) -> String?`: a known code gives its `text`; unknown text, such as a v2 Korean sentence, is returned unchanged; nil stays nil
  - `HelperPolicy.protocolVersion = 3`
  - `HelperPolicy.requirement(identifier: String, team: String?) -> String`. With a team it returns `identifier "<id>" and anchor apple generic and certificate leaf[subject.OU] = "<team>"`; without one it returns `identifier "<id>"`.
  - `HelperPolicy.clientRequirement(team:)` and `HelperPolicy.helperRequirement(team:)` replace the two static strings.
  - `public enum CodeSigningIdentity { public static func ownTeamID() -> String? }` in BatteryPlatform, using `SecCodeCopySelf` and `SecCodeCopySigningInformation` with `kSecCSSigningInformation`, then reading `kSecCodeInfoTeamIdentifier`.
  - `readState` sends `"none"` instead of `"없음"` for a missing key.

- [ ] **Step 1: Write failing tests in `HelperV3Tests.swift`**

```swift
@Test func pinnedRequirement() {
    #expect(HelperPolicy.requirement(identifier:"io.github.y-minion.vibebattery",team:"JQWWU7443A") ==
      "identifier \"io.github.y-minion.vibebattery\" and anchor apple generic and certificate leaf[subject.OU] = \"JQWWU7443A\"")
    #expect(HelperPolicy.requirement(identifier:"io.github.y-minion.vibebattery",team:nil) == "identifier \"io.github.y-minion.vibebattery\"")
}
@Test func replyCodesRoundTrip() {
    for r in HelperReply.allCases { #expect(HelperReply(rawValue:r.rawValue)==r); #expect(!r.text.isEmpty) }
    #expect(HelperReply.display("헬퍼가 예전 문장을 보냄") == "헬퍼가 예전 문장을 보냄")
    #expect(HelperReply.display(nil) == nil)
    AppLanguage.$forced.withValue(.en) { #expect(HelperReply.display("led.unsupported") == HelperReply.ledUnsupported.text) }
}
@Test func ledUnsupportedFromCodeOrV2Text() {
    #expect(MagSafeLEDPolicy.outcome(reply:"led.unsupported") == (true,true))
    #expect(MagSafeLEDPolicy.outcome(reply:"이 맥에서는 MagSafe LED를 바꿀 수 없습니다.") == (true,true))  // v2 helper
    #expect(MagSafeLEDPolicy.outcome(reply:"led.failed") == (false,false))
}
@Test func v2HelperIsOutdated() { #expect(HelperStatus.evaluate(installed:true,appPath:"/Applications/VibeBattery.app",probe:{true},version:{2}) == .outdated) }
```
Adapt the tuple comparison to whatever `outcome` returns.

- [ ] **Step 2: Run `swift test --disable-xctest --filter HelperV3Tests`.** Expected: FAIL.

- [ ] **Step 3: Implement.**
  - **Helper replies:** the helper replies only with `HelperReply` raw values.
  - **The v2 sentence:** a v2 helper's Korean "unsupported" sentence is kept as `MagSafeLEDText.legacyUnsupportedV2`, so `outcome(reply:)` still recognises it. That one line is not UI text, so it is not wrapped in `tr`. Instead the guard test gets an explicit `allowedLegacy: Set<String>` holding `"Sources/BatteryCore/MagSafeLEDPolicy.swift"` plus the constant's name, with a comment saying why.
  - **Helper CLI** (`--led …`): it prints English when not root-invoked with `VB_LANG=ko`, through `tr`. Root has no user language, so `VB_LANG` is how callers choose.
  - **App display:** every place the app shows a helper or control reply goes through `HelperReply.display`.
  - **Helper requirement for clients:** at startup the helper computes `HelperPolicy.clientRequirement(team: CodeSigningIdentity.ownTeamID())`. With nil it logs `NSLog("VibeBattery helper: self-built (ad-hoc), not team-pinned")`.
  - **App requirement for the helper:** `XPCChargeHelper` uses `helperRequirement(team: CodeSigningIdentity.ownTeamID())`.
  - **Low Power texts:** `LowPowerText.update` and the `unavailable` texts say why a reinstall is needed. English: "Reinstall the helper: this version only accepts the official VibeBattery app."

- [ ] **Step 4: Run `swift test --disable-xctest && swift build`.** Expected: PASS.

- [ ] **Step 5: Commit** — `feat: send helper replies as codes and pin the helper to the signing team`

### Task 3: Charge-limit platform gate

**Files:**
- Create: `Sources/BatteryCore/ChargeSupport.swift`, `Tests/BatteryCoreTests/ChargeSupportTests.swift`
- Modify: `Sources/BatteryPlatform/ChargeLimitClient.swift` (the read path and `limit(_:)` text), plus the view(s) that enable the limit controls

**Interfaces:**
- Produces:
  - `public enum ChargeSupport { public static func platformAllows(os: OperatingSystemVersion, arm64: Bool) -> Bool }`
  - `public static var current: Bool`, built from `ProcessInfo.processInfo.operatingSystemVersion` and the runtime arch
  - `public static var requirementText: String` = `tr("Charge limiting needs macOS 26.4 or later on Apple silicon (support for more Macs is planned).","충전 상한은 macOS 26.4 이상의 Apple Silicon 맥에서 쓸 수 있습니다(지원 기기 확대 예정).")`
  - For the runtime arch, use `#if arch(arm64)` combined with `sysctlbyname("sysctl.proc_translated")`: a Rosetta-translated x86 process on arm64 counts as arm64. Release builds are universal.

- [ ] **Step 1: Write failing tests**

```swift
@Test func gate() {
    #expect(!ChargeSupport.platformAllows(os:.init(majorVersion:26,minorVersion:3,patchVersion:9),arm64:true))
    #expect(ChargeSupport.platformAllows(os:.init(majorVersion:26,minorVersion:4,patchVersion:0),arm64:true))
    #expect(ChargeSupport.platformAllows(os:.init(majorVersion:27,minorVersion:0,patchVersion:1),arm64:true))
    #expect(!ChargeSupport.platformAllows(os:.init(majorVersion:27,minorVersion:0,patchVersion:0),arm64:false))
    #expect(!ChargeSupport.platformAllows(os:.init(majorVersion:15,minorVersion:7,patchVersion:0),arm64:true))
}
```

- [ ] **Step 2: Run, and expect FAIL.**

- [ ] **Step 3: Implement.**
  - When `!ChargeSupport.current`, the PowerUI read returns `ChargeLimitState(supported:false)` without calling PowerUI.
  - `ChargeStatusText.limit` returns `ChargeSupport.requirementText` for `supported == false`.
  - The app disables the limit controls and quick-limit buttons and shows that text.
  - Nothing is written on unsupported platforms. Existing write guards already require `supported == true`; verify it.

- [ ] **Step 4: Run `swift test --disable-xctest`.** Expected: PASS.

- [ ] **Step 5: Commit** — `feat: explain which Macs support charge limiting`

### Task 4: `vbctl` and script text in two languages

**Files:**
- Modify: `Sources/VibeCLI/*.swift`, `Sources/BatteryCore/ChargeCLI.swift` (usage)
- Modify: `scripts/install-helper.sh`, `scripts/uninstall-helper.sh`, `scripts/build-app.sh`, `scripts/smoke-sessions.py`
- Modify: `LocalizationTests` (remove from `pending`; add the script guard)
- Modify: `.github/workflows/ci.yml` (run smoke with `VB_LANG=en`)

**Interfaces:**
- Consumes: `tr` (Task 1).
- Produces a POSIX helper copied at the top of each script:

```sh
vb_lang() { case "${VB_LANG:-$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2s/[^a-z]*\([a-z]*\).*/\1/p')}" in ko*) echo ko;; *) echo en;; esac; }
msg() { if [ "$(vb_lang)" = ko ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }
```

- [ ] **Step 1: Write the failing test.** Add the `scriptsSayBothLanguages` guard to `LocalizationTests`: every line of `scripts/*.sh` containing Hangul must contain `msg `.

- [ ] **Step 2: Run it, and expect FAIL.**

- [ ] **Step 3: Implement.**
  - **vbctl text:** `vbctl` human output and usage go through `tr`. `--json` is unchanged.
  - **Scripts:** every user-facing script line goes through `msg "English" "한국어"`.
  - **smoke-sessions.py:** runs `vbctl` with `VB_LANG=en` and asserts the English text. Its Korean literals are removed.

- [ ] **Step 4: Run all checks.** Run `swift test --disable-xctest && swift build && python3 scripts/smoke-sessions.py .build/debug/vbctl && VB_LANG=ko .build/debug/vbctl charge status && VB_LANG=en .build/debug/vbctl charge status && sh -n scripts/*.sh`. Expected: all pass; the two status lines are Korean and English.

- [ ] **Step 5: Commit** — `feat: speak English or Korean in vbctl and the helper scripts`

### Task 5: App UI in two languages, part 1 (charge, settings, model)

**Files:**
- Modify: `Sources/VibeBattery/SettingsView.swift`, `ChargeView.swift`, `ChargeControlView.swift`, `AppModel.swift`, `DashboardView.swift`, `MenuWindow.swift`
- Modify: `LocalizationTests` (remove these from `pending`)

**Interfaces:**
- Consumes: `tr`, `HelperReply.display` (Tasks 1–2).

- [ ] **Step 1: Convert.** Every Hangul literal becomes `tr("English","원문")`.
  - SwiftUI `Text(tr(...))` is verbatim, which is intended.
  - Alerts, menu items, toggles, pickers and accessibility labels are all converted.
  - The conflict message keeps the competitor names in both languages.

- [ ] **Step 2: Run `swift test --disable-xctest && scripts/build-app.sh`.** Expected: PASS and the app builds.

- [ ] **Step 3: Commit** — `feat: show the charge, settings and dashboard screens in English or Korean`

### Task 6: App UI part 2, App Intents, in-app helper install

**Files:**
- Modify: `Sources/VibeBattery/HealthView.swift`, `SessionsView.swift`, `ProcessesView.swift`, `LowPowerView.swift`, `App.swift`, `MenuBarIcon.swift`, `Notifier.swift`, `ChargeIntents.swift`, `AppModel.swift`, `ChargeControlView.swift`
- Create: `Resources/ko.lproj/Localizable.strings`, `Resources/ko.lproj/AppShortcuts.strings`
- Modify: `project.yml` (`options.developmentLanguage: en`; app target resources include `Resources/ko.lproj`; Info `CFBundleDevelopmentRegion: en`, `CFBundleLocalizations: [en, ko]`), the regenerated `VibeBattery.xcodeproj`, `Package.swift` (exclude `Resources` from the SwiftPM `VibeBattery` target if needed)
- Modify: `LocalizationTests` (`pending` becomes empty; add `koreanStringsCoverIntents`)

**Interfaces:**
- Consumes: `tr`, `HelperReply` (Tasks 1–2).
- Produces:
  - `AppModel.installHelper() async -> String?`, which runs `do shell script "VB_LANG=<lang> '/Applications/VibeBattery.app/Contents/Resources/install-helper.sh'" with administrator privileges` through `NSAppleScript` off the main actor. It returns nil on success or the error text, then calls `checkHelper()`.
  - `AppModel.uninstallHelper() async -> String?`, the same for `uninstall-helper.sh`.

- [ ] **Step 1: Write the failing test `koreanStringsCoverIntents`.**
  - Parse every `LocalizedStringResource` literal key and every `AppShortcut` phrase in `ChargeIntents.swift` with a regex on `"…"` after `LocalizedStringResource=`, `title:`, `description:` and `phrases:`.
  - Assert each key exists in `Resources/ko.lproj/Localizable.strings` or `AppShortcuts.strings` (parse with `PropertyListSerialization`, since `.strings` is a plist format).
  - Assert no key contains Hangul.
  - Expected to fail first.

- [ ] **Step 2: Convert.**
  - **App Intents:** keys become English (for example `"Set Charge Limit"`), with the Korean original as the `ko.lproj` value. Phrases keep `\(.applicationName)`. Intent dialog and result strings built at runtime use `tr`.
  - **Remaining views and notifications:** use `tr`.
  - **Helper install:** "Install helper…" and "Reinstall helper…" buttons call `installHelper()` where the `sudo` command was shown. The `sudo` command remains as secondary copyable text.
  - **Self-built note:** when `CodeSigningIdentity.ownTeamID() == nil`, the helper card shows `tr("Self-built copy: the installed helper will not be team-pinned.","직접 빌드한 앱: 설치되는 헬퍼가 팀 서명으로 묶이지 않습니다.")`.

- [ ] **Step 3: Run `xcodegen generate && swift test --disable-xctest && swift build && scripts/build-app.sh`.**
  - Expected: PASS; `pending` is empty.
  - `dist/VibeBattery.app/Contents/Resources/ko.lproj/Localizable.strings` exists.
  - `Metadata.appintents` is present.

- [ ] **Step 4: Commit** — `feat: finish English and Korean screens, Shortcuts and in-app helper install`

### Task 7: New-version notice

**Files:**
- Create: `Sources/BatteryCore/UpdateCheck.swift`, `Sources/BatteryPlatform/ReleaseClient.swift`, `Tests/BatteryCoreTests/UpdateCheckTests.swift`
- Modify: `Sources/BatteryCore/UserPreferences.swift` (add `checkUpdates: Bool = true`, decoded with `decodeIfPresent ?? true`), `AppModel.swift`, `SettingsView.swift`, `MenuWindow.swift` (footer)

**Interfaces:**
- Produces:
  - `public struct SemVer: Comparable, Sendable { public init?(_ tag: String) }`. It accepts an optional leading `v` and `MAJOR.MINOR.PATCH`, with an optional `-pre` suffix. A pre-release sorts below the same core.
  - `public enum UpdateCheck { public static func newer(latestTag: String, current: String) -> SemVer?; public static let interval: TimeInterval = 86_400 }`
  - `public static func installCommand` = `"curl -fsSL https://github.com/y-minion/vibebattery/releases/latest/download/install.sh | sh"`
  - `public struct ReleaseClient { public static func latest() async -> (tag: String, url: URL)? }`. It uses URLSession with a 10 s timeout and `Accept: application/vnd.github+json`, sends no cookies, and returns nil on any failure or non-200 status.
  - `AppModel.availableUpdate: (version: String, url: URL)?`. It is checked at launch and then every `interval` while `prefs.checkUpdates`, and compared against `CFBundleShortVersionString`.

- [ ] **Step 1: Write failing tests**

```swift
@Test func semver() {
    #expect(UpdateCheck.newer(latestTag:"v0.10.0",current:"0.9.0") != nil)
    #expect(UpdateCheck.newer(latestTag:"v0.2.0",current:"0.2.0") == nil)
    #expect(UpdateCheck.newer(latestTag:"0.2.0",current:"0.1.0") != nil)
    #expect(UpdateCheck.newer(latestTag:"v0.2.0-beta.1",current:"0.2.0") == nil)
    #expect(UpdateCheck.newer(latestTag:"v0.3.0-beta.1",current:"0.2.0") != nil)
    #expect(UpdateCheck.newer(latestTag:"nightly",current:"0.2.0") == nil)
    #expect(UpdateCheck.newer(latestTag:"v1.0",current:"0.2.0") == nil)
}
@Test func prefsDefaultOnAndOldFilesDecode() throws {
    let p = try JSONDecoder().decode(UserPreferences.self, from: Data("{}".utf8)); #expect(p.checkUpdates)
}
```

- [ ] **Step 2: Run, and expect FAIL.**

- [ ] **Step 3: Implement.**
  - **Settings:** a "Check for new versions" toggle. When an update is known: "New version x.y.z", an "Open release page" link, and "Copy install command".
  - **Menu window:** the footer shows "Update x.y.z" only when one is available.
  - **Debug override** (for validation only): env `VB_FAKE_CURRENT_VERSION` replaces the bundle version.

- [ ] **Step 4: Run `swift test --disable-xctest && scripts/build-app.sh`.** Expected: PASS.

- [ ] **Step 5: Commit** — `feat: tell people when a new version is out`

### Task 8: Release, install and uninstall scripts; universal, timestamped builds; 0.2.0

**Files:**
- Create: `scripts/release.sh`, `scripts/install.sh`, `scripts/uninstall.sh`, `scripts/test-install.sh`, `docs/release-notes/0.2.0.md`
- Modify: `scripts/build-app.sh` (when `VB_RELEASE=1`, refuse ad-hoc, add `--timestamp` to every `codesign --force`, and fail unless `codesign -dvv` shows `Timestamp=`; always print `lipo -archs` of the app binary)
- Modify: `project.yml` / xcodeproj (`MARKETING_VERSION: 0.2.0`; Release `ARCHS: "$(ARCHS_STANDARD)"`, `ONLY_ACTIVE_ARCH: NO`)
- Modify: `.github/workflows/ci.yml` (add `sh -n` for the new scripts and run `scripts/test-install.sh`)

**Interfaces:**
- Consumes: `UpdateCheck.installCommand` text (Task 7); `vbctl charge off`; `uninstall-helper.sh`; `msg` (Task 4).
- **`install.sh`:**
  - Env overrides for tests: `VB_RELEASE_BASE` (default `https://github.com/y-minion/vibebattery/releases/latest/download`), `VB_INSTALL_DIR` (default `/Applications`) and `VB_SKIP_OPEN`.
  - Asset names: `VibeBattery.zip` and `VibeBattery.zip.sha256`. `release.sh` uploads under these fixed names so `latest/download` works.
  - It runs in this order:
    1. Check `sw_vers -productVersion` ≥ 15, and print a support line from the OS and `uname -m`.
    2. Check the install dir is writable, else stop with the admin message.
    3. Download both files to `mktemp -d`.
    4. Check `shasum -a 256 -c`, aborting on mismatch.
    5. Unzip with `ditto -x -k`.
    6. Quit with `osascript -e 'quit app "VibeBattery"'`, ignoring a not-running app.
    7. `ditto` to `$VB_INSTALL_DIR/.VibeBattery.app.new`, then `rm -rf` the old copy and `mv` the new one into place.
    8. Run `open` unless `VB_SKIP_OPEN`.
    9. Print the uninstall line.
- **`uninstall.sh`:**
  1. If the app runs, ask "Turn off the macOS charge limit too? [y/N]" and run `vbctl charge off` on `y`.
  2. Quit the app. The app restores the MagSafe LED to system on quit.
  3. Run `uninstall-helper.sh` via `osascript … with administrator privileges` if the helper plist exists.
  4. Remove the app.
  5. Ask "Delete VibeBattery data (history, settings)? [y/N]" and, on `y`, run `rm -rf ~/Library/Application\ Support/VibeBattery` and `defaults delete io.github.y-minion.vibebattery`.
  - It reads answers from `/dev/tty` so it works under `curl | sh`.
- **`release.sh <version>`:**
  1. Refuse unless the tree is clean, on `main`, equal to `origin/main`, the `MARKETING_VERSION` in `project.yml` equals `<version>`, the tag doesn't exist, and `docs/release-notes/<version>.md` exists.
  2. Run `VB_RELEASE=1 scripts/build-app.sh`.
  3. Check `lipo -archs` lists `arm64` and `x86_64`.
  4. Write the checksum.
  5. Print a summary and ask `Publish v<version>? [y/N]`.
  6. Run `git tag -a v<version>` and `git push origin v<version>`.
  7. Run `gh release create v<version> --title "VibeBattery <version>" --notes-file docs/release-notes/<version>.md` with the four assets, and never pass `--prerelease`.

- [ ] **Step 1: Write the failing `scripts/test-install.sh`.**
  - Build a fake release dir from `dist/VibeBattery.zip` and its checksum, then run `install.sh` with `VB_RELEASE_BASE=file://…`, `VB_INSTALL_DIR=$(mktemp -d)` and `VB_SKIP_OPEN=1`. Assert the app exists and `codesign --verify --strict` passes.
  - Corrupt the checksum and assert a nonzero exit, with the install dir unchanged.
  - Run with an unwritable dir (`chmod 555`) and assert a nonzero exit and the admin message.
  - It is expected to fail first, because `install.sh` is missing.

- [ ] **Step 2: Implement the scripts, the build-app changes, the version bump and `docs/release-notes/0.2.0.md`.**
  - The notes come in two sections: English first, then Korean. They mark the release as a beta and list requirements honestly.
  - They name no competitor and make no lifespan claims.
  - They tell 3-3 users to reinstall the helper.

- [ ] **Step 3: Run the checks.** Run `scripts/build-app.sh && lipo -archs dist/VibeBattery.app/Contents/MacOS/VibeBattery && sh scripts/test-install.sh && sh -n scripts/release.sh scripts/install.sh scripts/uninstall.sh`.
  - Expected: `x86_64 arm64` and the tests pass.
  - Then run `VB_RELEASE=1 scripts/build-app.sh` once locally. Report whether Apple's timestamp server accepted the development certificate. If it refused, stop and report; do not work around it.

- [ ] **Step 4: Commit** — `build: add release, install and uninstall scripts for 0.2.0`

### Task 9: Measured facts and the "why a limit helps" explainer

**Files:**
- Modify: `Sources/BatteryCore/HealthReport.swift` and `HealthLedger.swift` (add `previousWeek: UsageSummary`, the 7 days before `week`, decoded with `decodeIfPresent ?? UsageSummary()`), `Sources/VibeBattery/HealthView.swift`, `Sources/VibeBattery/DashboardView.swift` (health card)
- Create: `Sources/BatteryCore/ChargeLimitExplainer.swift` (`public enum ChargeLimitExplainer { public static var paragraphs: [String]; public static let sources: [(title: String, url: URL)] }`)
- Test: `Tests/BatteryCoreTests/HealthReportTests.swift`

**Interfaces:**
- Produces:
  - `HealthReport.previousWeek`
  - `public static func factLines(_ r: HealthReport) -> [String]` in `HealthReport` text. The lines are:
    - hours ≥90% this week vs the previous week
    - hours ≥95% this week vs the previous week
    - hours ≥35 °C this week vs the previous week
    - hours ≥40 °C this week vs the previous week
    - cycles
    - health with the "(estimate)" or "(추정)" label
  - Format: `"≥90% charge: 112.0 h → 3.0 h"` or, without a previous week, `"≥90% charge: 3.0 h"`.

- [ ] **Step 1: Write failing tests.** `factLines` for a report with `previousWeek.soc90 = 403200`, `week.soc90 = 10800`, under `.en`, contains `"≥90% charge: 112.0 h → 3.0 h"`. Under `.ko` it contains `"잔량 90% 이상: 112.0시간 → 3.0시간"`. With an empty `previousWeek` there is no arrow. Old JSON without `previousWeek` decodes.

- [ ] **Step 2: Run, and expect FAIL.**

- [ ] **Step 3: Implement.**
  - **Health card:** it leads with `factLines`, then the existing trend and stress lines. A "Why a charge limit helps" disclosure shows `ChargeLimitExplainer.paragraphs` and the source links: Apple `https://support.apple.com/102338` and Battery University BU-808 `https://batteryuniversity.com/article/bu-808-how-to-prolong-lithium-based-batteries`.
  - **Explainer text:** time at high charge and heat speeds up wear, and a limit cuts that time. It contains no numbers about lifespan.
  - **Copy audit:** check every user-visible string for unmeasurable claims and competitor names, outside the conflict-safety exception.

- [ ] **Step 4: Run `swift test --disable-xctest && scripts/build-app.sh`.** Expected: PASS.

- [ ] **Step 5: Commit** — `feat: lead the health card with measured facts and explain why limits help`

### Task 10: Storefront — READMEs, site, community files, launch drafts

**Files:**
- Rewrite: `README.md` (English)
- Create: `README.ko.md`, `CONTRIBUTING.md`, `SECURITY.md`, `.github/ISSUE_TEMPLATE/bug_report.yml`, `.github/ISSUE_TEMPLATE/feature_request.yml`, `site/index.html`, `site/ko/index.html`, `site/style.css`, `.github/workflows/pages.yml`, `docs/launch/velog.md`, `docs/launch/geeknews-okky-clien.md`, `docs/launch/reddit-macapps.md`, `docs/launch/show-hn.md`, `scripts/capture.md`
- Modify: `docs/COMPATIBILITY.md` (support matrix, the helper protocol 3 and team pinning, the timestamp result from Task 8), `docs/VALIDATION.md` (a section "Free distribution (2026-10-28)" with the spec's five validation steps, each marked checked or not yet)

- [ ] **Step 1: Write the READMEs.**
  - **First screen:** the language link, then the message ("A laptop's lifespan is decided by its battery. VibeBattery keeps yours healthy for longer — and features other apps charge for are all free here."), a capture placeholder `docs/images/menu-window.gif` referenced from `scripts/capture.md`, the install one-liner, and "First thing: set the limit to 80%".
  - **Then:**
    - features, under the heading "Features other apps charge for — all free here"
    - the requirements matrix
    - browser download and "Open Anyway" steps for macOS 15+
    - an explanation of why curl installs need no prompt, with a link to the `install.sh` source
    - safety notes, including the conflicting apps by name
    - the helper explained, and uninstall
    - build from source, with the self-built note
    - privacy: only the version check talks to the network
  - The Korean README carries the same content in natural Korean.

- [ ] **Step 2: Write the rest.**
  - **Site:** static HTML/CSS with no external resources, in English and Korean, with the install line and a download button that points at `releases/latest`.
  - **Pages workflow:** `actions/upload-pages-artifact` + `actions/deploy-pages` from `site/`, triggered on push to `main` when `site/**` changes.
  - **SECURITY.md:** what the root helper can do (fixed requests, one SMC key, no shell) and how to report problems (GitHub private vulnerability reporting).
  - **CONTRIBUTING.md:** how to build and test, the self-built pinning note, and the PR flow.
  - **Issue templates:** the bug template asks for Mac model, macOS version and `vbctl charge status`.
  - **Launch drafts:** follow the message and the anti-goals, and each ends with the install line and the repo link.
  - **`scripts/capture.md`:** lists the shots (menu window, dashboard power flow, health card facts, settings LED) in each language, with `screencapture -l` commands.

- [ ] **Step 3: Verify.**
  - Check `grep -n -i "aldente" README.md README.ko.md site docs/launch docs/release-notes` returns only the safety-note lines.
  - Check `grep -n -iE "years longer|months longer|% longer|년 더|개월 더" README* site docs/launch docs/release-notes` returns nothing.
  - Check every relative link in both READMEs resolves.

- [ ] **Step 4: Commit** — `docs: open-source storefront in English and Korean`

## After the tasks (controller, with the owner)

These are outward-facing steps, and the owner confirms each one.
1. Push and open the PR, then wait for CI to pass.
2. Run the on-device validation steps from the spec. This includes reinstalling the helper and checking the ad-hoc app is refused.
3. Merge.
4. `gh repo edit` the description and topics, and enable Pages.
5. The owner records the captures.
6. Run `scripts/release.sh 0.2.0`.
7. The owner posts the launch drafts.
