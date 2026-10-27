# 3-4 Free distribution (no paid Apple Developer Program) — design

Date: 2026-10-28. Follows 3-3 (PR #5). 3-5 (Intel Macs and older macOS charge limiting) is a separate, required follow-up project with its own design; this document only prepares for it.

## Intent and why

The owner wants as many Mac users as possible, in Korea and abroad, to use VibeBattery for free. The owner and the users both pay nothing. The owner will not join the $99/yr Apple Developer Program, so there is no Developer ID signing and no notarization.

The owner considers the feature set already sufficient. Success is adoption, not more features.

People install a battery app because someone they trust wrote "use this to keep your battery healthy". The owner installed the competitor that way, from a velog post, without ever seeing a number. So:

- **The message:** "A laptop's lifespan is decided by its battery. VibeBattery keeps your battery healthy for longer. Features other apps charge for are all free here."
- **Getting the first install:** recommendation posts and the README. They must make installing and the first step trivially easy.
- **Getting people to recommend it:** after install the app shows measured facts (time spent at high charge and heat, and how much it went down). Only those facts back the message. Competitors show no such numbers, so this is the differentiator.

## Goals

1. **Installing is one step.**
   - A one-line terminal install, or a GitHub Releases download with clear Gatekeeper ("Open Anyway") steps.
   - Uninstalling is just as easy.
2. **Every Mac user can read it.** The app UI and all public copy come in English and Korean.
3. **The repository is the storefront.**
   - An English README with a separate Korean README.
   - A free GitHub Pages landing page.
   - Ready-to-post launch drafts in both languages.
4. **Claims are honest.** Public copy and in-app copy only state measured facts, or cited general research labelled as such.
5. **The root helper trusts only official builds.** No paid program is needed for this.
6. **Users learn about new versions.** No auto-install.

## Non-goals

- Charge limiting on Intel Macs or macOS older than 26.4. That is project 3-5.
- Homebrew. The official cask repo drops unnotarized casks from 2026-09, and a personal tap still shows the Gatekeeper block while its `--no-quarantine` escape is deprecated. Revisit after 3-5.
- Auto-update frameworks such as Sparkle.
- App Store distribution.
- Analytics or telemetry of any kind.
- New battery metrics or features. Existing data is enough; see "Measured facts".

## Anti-goals (would be a failure even if it works)

- **Naming a competitor in public copy, or pitching it as "X Pro for free".** This covers the README, site, posts, release notes and app UI.
  - The one exception is the factual safety note that lists charge managers VibeBattery refuses to run alongside (AlDente, batt, battery, Battery Toolkit). Users need those names to recognise the conflict.
- **Lifespan claims that cannot be measured**, such as "adds 2 years" or "extends life by 30%".
- An install path that needs sudo in the terminal, or that silently installs the root helper.
- Sending any user data anywhere. The only network request allowed is the version check.
- Requiring the owner to pay for anything, including hosting.

## Constraints

- **Signing identity:** the owner's free-account "Apple Development" certificate.
  - Its team ID is the subject OU, `JQWWU7443A`. The `97D9DBLX9K` shown in the certificate name is not the team ID.
  - It expires on 2027-10-23.
  - Shortcuts only lists actions from team-signed apps, so release builds are signed with it.
  - CI cannot sign. The certificate must not be uploaded anywhere, and `dev.pem` is never committed.
- **Support matrix today:**
  - Apple Silicon + macOS 26.4+ gets every feature. Charge Limit is a macOS 26.4+ / Apple-silicon feature that VibeBattery drives.
  - macOS 15–26.3 and Intel get everything except charge limiting.
  - Today the app only says "not supported" when PowerUI answers NO. When the PowerUI class or selector is missing, which is likely on 15.x, it says "limit unknown". 3-4 adds an explicit check: below macOS 26.4 or on Intel the limit controls are disabled and say "Charge limiting needs macOS 26.4 or later on Apple silicon (support for more Macs is planned)". *(my call: it makes the requirements matrix true, and it does not write anything.)*
  - Only one Mac (M4 Pro, macOS 27.0.1) is validated by hand. CI builds and runs read-only checks on macOS 15.
- **Shell:** the install script must run on stock macOS 15+ with only `/bin/sh`, `curl`, `shasum` and `ditto`.
- **Safety:** existing safety behaviour (conflict blocking, helper allow-lists, the LED dirty flag) stays unchanged.

## Decided parts

### 1. Release build and publishing

- **Version:** `MARKETING_VERSION` goes from 0.1.0 to **0.2.0** for the first public release, labelled beta in the notes only. *(my call: one validated Mac does not justify 1.0.)*
  - The release is never marked as a GitHub pre-release. `releases/latest` skips pre-releases, which would break the install one-liner and the version check.
  - The version bump lands through a normal PR, in both `project.yml` and the committed xcodeproj. `release.sh` only checks that `main` already carries the version it was given; it never commits or pushes to `main`. *(my call)*
- **`scripts/release.sh <version>`** runs locally on the owner's Mac. It:
  1. checks the tree is clean, on `main`, up to date with `origin/main`, and already at `<version>`
  2. builds with `scripts/build-app.sh`, failing if the identity is ad-hoc. Release signing adds a secure timestamp (`codesign --timestamp`), and the script checks that `codesign -dvv` shows one, so signatures stay valid after the certificate expires. *(my call)* If Apple's timestamp server refuses a development certificate, the builder stops and reports it; the fallback is a re-release and a helper reinstall before each certificate expiry.
  3. writes `VibeBattery-<version>.zip` and its `.sha256`
  4. tags `v<version>`
  5. creates the GitHub release with `gh`, with English then Korean notes from `docs/release-notes/<version>.md`
  6. uploads the zip, the checksum, `install.sh` and `uninstall.sh`
- **Confirmations:** the script prints what it will publish and asks before the tag push and the release. Publishing is the owner's action.
- **Universal binary:** release builds are universal (arm64 + x86_64), so Intel Macs on macOS 15+ can already use the monitoring features and 3-5 needs no packaging change. *(my call)* The builder confirms the build settings produce both slices, and `release.sh` checks with `lipo -archs`.

### 2. Install and uninstall

- **`install.sh`** lives in the repo. The README one-liner fetches it from the latest release asset, not from `main`, so it matches the zip:
  `curl -fsSL https://github.com/y-minion/vibebattery/releases/latest/download/install.sh | sh`
- **What `install.sh` does:**
  1. checks macOS ≥ 15 and prints what will and will not work on this Mac (no charge limit below 26.4 or on Intel)
  2. downloads the zip and checksum from the same release and verifies SHA-256, aborting on mismatch
  3. quits a running VibeBattery
  4. installs to `/Applications` with `ditto`, never with sudo. The helper only serves `/Applications/VibeBattery.app`, so there is no `~/Applications` fallback. If `/Applications` is not writable (a standard, non-admin account), the script stops and says an administrator must install it. *(my call: personal MacBooks are almost always admin accounts, and the helper allow-list stays unchanged.)*
  5. opens the app
  6. prints the uninstall line
- **Why no Gatekeeper prompt:** curl downloads carry no quarantine attribute. The README says so plainly and shows the script source, so readers can check it before piping it to `sh`.
- **The root helper** is still installed only from inside the app, through the existing admin-password dialog, and only when the user picks a limit below 80% or another helper feature.
- **`uninstall.sh`:**
  - always removes the app
  - removes the helper through the existing `uninstall-helper.sh`, asking for the admin password via the macOS dialog
  - asks before deleting `~/Library/Application Support/VibeBattery` and the app's defaults, which default to kept
  - while the app still runs: restores the MagSafe LED to system, and asks whether to keep the macOS Charge Limit as it is (default: keep, since macOS keeps enforcing it without VibeBattery and it shows in System Settings) or turn it off with `vbctl charge off`. `vbctl` writes go through the running app, so this happens before the app is quit. *(my call)*
- **Browser download:** the README documents the macOS 15+ flow (open once → System Settings → Privacy & Security → "Open Anyway"), with a screenshot in each language.

### 3. Helper trust without Developer ID

- **Today:** the helper accepts any client whose signing identifier is `io.github.y-minion.vibebattery`, and an ad-hoc-signed app can claim that.
- **New rule:**
  - The client requirement adds `anchor apple generic and certificate leaf[subject.OU] = "<team>"`.
  - The app's requirement for the helper gets the same addition.
  - `<team>` is baked in at build time from the signing identity. `build-app.sh` reads the OU of the identity it signs with.
- **Ad-hoc builds** (CI, source builders without a certificate) keep the identifier-only rule, and their helper logs and replies a "self-built, not team-pinned" notice. *(my call)* Only root can replace an installed helper, so a self-built helper is the user's own choice.
- **Protocol:** the helper protocol version goes up, so the app's existing version check asks 3-3 users to reinstall the helper once. The reinstall prompt explains why, in both languages.
- **Test:** helper and app agree on the pinned requirement string. Requirement strings are unit-tested.
- **Validation:** after the certificate's expiry date cannot be tested, so the timestamp check in `release.sh` is the guard.

### 4. New-version notice

- **The check:** once a day, while the app runs, it calls `GET https://api.github.com/repos/y-minion/vibebattery/releases/latest` with no identifying data, and compares versions with semver.
- **Where it shows:** the settings and the menu window footer show "New version x.y.z". They link to the release page and offer a button that copies the install line.
- **The toggle:** a Settings toggle "Check for new versions", on by default. *(my call)* Network failure is silent.

### 5. English and Korean

- **Language rule:** English is the base language and Korean the translation. The app follows the macOS preferred language, and any language other than Korean falls back to English.
- **What gets translated:**
  - SwiftUI views and menus
  - notifications
  - App Intents titles, parameters, dialogs and App Shortcuts phrases
  - alerts
  - the menu bar accessibility labels
  - `vbctl` human output; `--json` output is not translated and its keys stay stable
- **Mechanism:** String Catalogs (`.xcstrings`) per target that has user-visible text. All 583 Korean literals in 38 files move to keys.
  - Text that crosses a process boundary (helper replies, the control channel) must become stable codes, localized at display time in the app or CLI.
  - Comparisons against reply text, such as `MagSafeLEDPolicy.outcome(reply:)`, must compare codes, not Korean sentences.
- **Formatting:** numbers, percentages, durations and dates use locale-aware formatting.
- **Tests:**
  - assert codes and both catalogs for key strings
  - a test fails if any catalog key lacks a Korean or English value
  - a test fails if a Hangul literal remains in Swift sources outside catalogs and tests

- **Scope of the 583 literals:** they span 39 Swift files. Multi-line `"""` text and the Korean output of the shell scripts (`install-helper.sh`, `uninstall-helper.sh`, `build-app.sh`) are also translated. The helper's Korean replies, including `readState`'s "없음", become codes.

### 6. Measured facts (copy, not new metrics)

- **The health card and the weekly summary lead with facts the app already records:**
  - hours at ≥90% and ≥95% charge
  - hours at ≥35 °C and ≥40 °C
  - each compared with the previous period
  - cycles, and capacity-based health labelled as an estimate
- **The "if the limit had been 80%" comparison** stays labelled as relative stress from general Li-ion research (Battery University BU-808). It never turns into months or years.
- **A short "Why a charge limit helps" explainer**, in the app (linked from the health card) and on the site, cites Apple's Charge Limit support article (support.apple.com/102338) and BU-808.
- **Audit:** the builder reviews every user-visible claim against this section.

### 7. Repository as storefront

- **README:**
  - `README.md` is in English and `README.ko.md` in Korean, with a language link at the top of each.
  - The first screen has the message, an animated capture of the menu window, the install one-liner, and "First thing: set the limit to 80%".
  - Then come features, framed as "features other apps charge for — all free here", followed by requirements as an honest matrix, safety notes and uninstall.
  - The current Korean README text that names the competitor ("모든 AlDente 기능…", "AlDente Pro 기능의 무료 대응") is rewritten. The conflict-safety note keeps the names, and so does the conflict message in Settings (`SettingsView.swift:40`, "AlDente 등이 감지되어…"), which is the same safety exception.
- **Landing page:** static HTML in `site/` with en and ko, deployed by a GitHub Pages Actions workflow. It has no trackers, fonts or scripts from third parties.
- **Captures:** screenshots and GIFs come from the owner's Mac. The builder writes `scripts/capture.md` with the exact shots needed, and a script for the parts `screencapture` can automate.
- **Open-source hygiene:**
  - `CONTRIBUTING.md`, which covers how to build from source and the team-pinning note for self-builds
  - `SECURITY.md`, which explains the root helper's surface and how to report problems
  - issue templates for a bug report (Mac model, macOS version, `vbctl charge status` output) and a feature request
  - repo topics: macos, battery, menubar, swiftui, battery-health
  - an English repo description
- **Launch drafts:**
  - `docs/launch/` holds a velog post (ko), a GeekNews/OKKY/클리앙 post (ko), a Reddit r/macapps post (en) and a Show HN post (en).
  - They follow the message and anti-goals above.
  - The owner posts them. Claude never posts anywhere.

### 8. Measuring success

- Success is GitHub stars and release download counts, which GitHub shows for free.
- Nothing in the app counts users.

## Left to the builder

- **Code layout:** the exact file layout of the catalogs, the version-check client and the scripts.
- **Wording:** the wording in both languages, within the message and anti-goals.
- **Site:** its visual design.
- **Task order:** a suggested order is localization infrastructure → helper pinning → version check → scripts → docs/site/drafts.

## Validation (on the owner's Mac)

1. **Install from a clean state:** use the one-liner, then the browser zip with the "Open Anyway" flow.
2. **Language:** switch the macOS language to English and check the UI, notifications, Shortcuts and `vbctl`, then switch back.
3. **Helper pinning:**
   - Reinstall the helper.
   - An ad-hoc-signed copy of the app is refused by the pinned helper.
   - The official build works: limit 70, Low Power and LED.
4. **Version notice:** point the version check at a fake older version and confirm the notice appears.
5. **Uninstall:** run `uninstall.sh` and confirm the app, helper and LaunchDaemon are gone, and the data is kept or removed per the answer.
