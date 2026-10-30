# Easy install, first run and in-app update — design

Date: 2026-10-30. Lands on `feat/free-distribution` (PR #7) before the first public release, 0.2.0. It builds on the free-distribution design (`2026-10-28-free-distribution-design.md`); the app was renamed Save the Battery on the same branch.

## Intent and why

The owner walked through a browser install on a real Mac and found it far too complicated for an ordinary person:

1. Unzip.
2. Drag the app to Applications by hand.
3. Open it and get a warning.
4. Find System Settings › Privacy & Security › Open Anyway and enter a password.
5. Install the helper with another password.

A normal Mac app is "drag to Applications, done". The owner asked whether the terminal step could be avoided too, for example by a button that runs the command. It cannot. A web page cannot run commands on a Mac, and anything downloaded to run them gets the same Gatekeeper warning.

The cause of step 4 is that the app is not notarized. Notarization needs the paid Apple program, which the owner has ruled out. So the warning cannot be removed for browser downloads. Everything else can be made simpler, and after the first install the user should never need Terminal again.

The owner agreed to five changes:
- a one-line terminal install as the main path;
- a DMG download for browser users;
- a first-run guide in the app;
- an "Update" button in the app;
- a simpler helper install.

## Goals

1. **The main install path has no warning.** The site and the READMEs lead with "copy the command, open Terminal, paste, press Enter". A copy button and three short steps explain it. The installer already places the app in /Applications and opens it.
2. **The browser path looks like a normal Mac app.** The download is a DMG with the app and an Applications shortcut, so the user drags one icon. Open Anyway is still needed once, and the site and READMEs show it as a numbered step.
3. **The first run fixes the common mistakes.**
   - Opened from anywhere other than `/Applications/Save the Battery.app`, the app offers "Move to Applications" and does it.
   - The app offers "Set 80%" as the recommended first step, which needs no helper.
4. **Updates are one click.** When a newer release exists, the app shows "Update now". It downloads, verifies, replaces itself and relaunches. No Terminal, no Gatekeeper prompt.
5. **The helper takes one click and one password, only when needed.**
   - Picking a limit below 80% (or the LED or Low Power switch) offers "Install helper and apply" right there.
   - The password dialog explains why it is asking.

## Non-goals

- Removing Open Anyway for browser downloads (impossible without notarization).
- Background auto-install or silent updates. The update always waits for the user's click.
- Sparkle or other update frameworks.
- A custom DMG background image or window layout. It needs Finder scripting, which is flaky in CI. Revisit later.
- `SMAppService` daemons for the helper. They need an extra approval toggle in System Settings and a different helper layout, and it is unclear how they behave with a free Apple Development certificate. That is not simpler than one password dialog.
- Renaming "helper" in the UI.
- Homebrew (see the earlier design).

## Anti-goals

- An updater that would install anything not signed by the same team as the running app.
- An updater that leaves the user with no app after a failure.
- Deleting a copy the user might still need, such as the app inside a mounted DMG.
- Copy that hides the Open Anyway step or calls it optional.

## Design

### 1. Terminal first (site, READMEs)

- **Site, both languages:** the first button copies the install command (clipboard API, with a visible "Copied" state). Below it are three numbered steps:
  1. Press ⌘+Space, type "Terminal", press Enter.
  2. Paste with ⌘V.
  3. Press Enter. The app opens by itself.

  The second button is "Download (.dmg)", linking straight to `releases/latest/download/savethebattery.dmg`, with the Open Anyway steps under it.
- **READMEs:** the same order and the same three steps. Browser download becomes "Download `savethebattery.dmg`, drag the app to Applications, open it, then Open Anyway".
- `install.sh` behaviour is unchanged.

### 2. DMG

- `scripts/build-app.sh` also writes `dist/savethebattery.dmg`, a compressed (UDZO) HFS+ image named "Save the Battery". It holds `Save the Battery.app` and an `Applications` symlink. It is signed with the same identity, with a timestamp in release builds.
- `scripts/release.sh` uploads `savethebattery.dmg` next to the zip and adds a matching `savethebattery.dmg.sha256` for people who verify by hand.
- The zip stays. `install.sh` and the in-app updater use it.
- `scripts/test-install.sh` also checks that the DMG mounts read-only and contains both items.

### 3. First run

**Move to Applications.**
- **When it shows:** when the app's real location is not `/Applications/Save the Battery.app`, it shows a card at the top of the dashboard and the menu window: "Move Save the Battery to Applications?" with a **Move** button and a dismiss. The real location is:
  - the bundle path; or
  - under App Translocation, the original path from `SecTranslocateCreateOriginalPathForURL`. It is looked up with `dlsym` in Security.framework; if it is missing, the app treats the bundle path as the location.
- **What Move does:**
  1. `ditto` the bundle to `/Applications/.Save the Battery.app.new`. `ditto` keeps extended attributes, so the user's Open Anyway approval travels with it.
  2. Move any existing `/Applications/Save the Battery.app` aside, then move the new copy into place. On failure, restore the old one.
  3. Launch the new copy and quit.
  4. Move the original to the Trash with `NSWorkspace.recycle` if it is on a writable volume. Never touch a read-only volume, such as the DMG.
- **Why trash the original:** two copies with the same bundle ID confuse Launch Services and Shortcuts.
- **When /Applications is not writable** (a standard account): say so ("ask an administrator") and change nothing.
- **Development builds** (an ad-hoc signature, or a path under the repository's `dist/`) still show the card, because the helper only serves `/Applications`. The developer can dismiss it.

**Set 80% card.**
- **When it shows:** on the dashboard, when:
  - charge limiting is supported (`ChargeSupport.current` and macOS reports it);
  - no other charge manager is detected;
  - the macOS limit is off or at 100%;
  - the user has not dismissed the card.
- **What it offers:** "Recommended: stop charging at 80%", with **Set 80%** (`applyCharge(.setLimit(80))`) and **Not now**.
- **Saving the dismissal:** in `preferences.json` (a new optional field, decoded leniently).
- **When it hides:** once any limit below 100% is in force.

### 4. In-app update

The update notice (Settings › Updates) gets **Update now** in place of "Copy install command". The release page link stays. The command stays as a fallback under "Install from Terminal instead" when the updater is unavailable.

**When the updater is available:** all of these must hold.
- The running app is `/Applications/Save the Battery.app`.
- The running app is team-signed (`CodeSigningIdentity.own` is `.team`).
- `/Applications` is writable by the user.

Otherwise the notice shows the command and the reason.

**Steps.** Each step either finishes or stops with a message and leaves the installed app untouched until step 7.

1. **Fetch the release.** Decode the latest release with its `assets` (`name`, `browser_download_url`).
2. **Pick the assets.** Take `savethebattery.zip` and `savethebattery.zip.sha256`. Their URLs must start with `https://github.com/y-minion/savethebattery/releases/download/`. Redirects to GitHub's download host are followed; integrity rests on steps 4 and 6, not on the host.
3. **Download.** Get both into a fresh temp directory with an ephemeral session. The zip must be at most 200 MB.
4. **Check the checksum.** The `.sha256` file must hold the zip's SHA-256 (CryptoKit). Format: 64 hex digits, optionally followed by the file name.
5. **Extract.** Run `/usr/bin/ditto -x -k` into the temp directory. It must yield exactly one `Save the Battery.app` at the top level.
6. **Check the new app.**
   - **Signature:** `SecStaticCodeCheckValidity` with the `kSecCSStrictValidate` and `kSecCSCheckAllArchitectures` flags, against the same requirement the helper uses for clients: `HelperPolicy.clientRequirement(.team(ownTeam))`, that is the identifier `io.github.y-minion.savethebattery`, an Apple anchor and the same team as the running app.
   - **Version:** its `CFBundleShortVersionString` must equal the release tag's version and be newer than the running version. No downgrade, no replay of an old release.
7. **Swap.**
   1. Move `/Applications/Save the Battery.app` to `/Applications/.Save the Battery.app.old`. The running process keeps its open files.
   2. Move the new app into place. If that fails, move the old one back and report.
8. **Relaunch.**
   1. Start a detached `/bin/sh` that waits for this PID to exit, runs `open "/Applications/Save the Battery.app"`, then removes the `.old` copy and the temp directory.
   2. Then quit normally, which hands back the LED and the heat hold as on any quit.

**No Gatekeeper prompt.** Files the app downloads itself get no quarantine flag, because the app does not set `LSFileQuarantineEnabled`. Verify this on the device.

**If the helper protocol changed.** After relaunch, the existing `outdated` status asks for a reinstall. No new code is needed.

**Testing hook.** The `STB_RELEASE_FEED` environment variable points the updater at a local JSON file. It also lets asset URLs be `file://` URLs inside that file. Signature and version checks are unchanged, so the hook cannot install anything the team did not sign. It exists so the flow can be tested on a device before a real release.

**Where the code goes.** Pure logic goes in BatteryCore, with tests:
- asset selection and the URL rules;
- checksum file parsing;
- the version guard;
- the availability rules.

The file work (download, extract, verify, swap) goes in BatteryPlatform. It is tested with temp directories where possible, and the swap step on its own.

### 5. Helper install

- **Apply with install:** in the charge card, a limit below 80% with no usable helper no longer disables **Apply**. The button reads "Install helper and apply…" and runs `installHelper()`; on success, the limit is applied. The LED and Low Power controls do the same: when the helper is missing, using them offers the install, then applies the choice.
- **Explained dialog:** the `osascript` call adds `with prompt` with a short reason in the app's language: "Save the Battery needs your password once to install its helper. It is used for limits below 80%, Low Power Mode and the MagSafe LED." Check on the device how the system dialog shows it.
- **Fallback tucked away:** the Terminal command moves into a collapsed "Install from Terminal instead" disclosure.
- **No change after updates:** no reinstall is needed unless the helper protocol version changes. That is already the case; the README says so.

## Constraints

- All new copy in English and Korean, through `tr(en, ko)`. Public copy names no competitor.
- The only SMC write remains `ACLC` 0, 1, 3 and 4. No new privileged operation.
- The updater only replaces `/Applications/Save the Battery.app`, never another path.
- No new network endpoints beyond the GitHub release API and that release's assets. The privacy text in Settings, README and SECURITY mentions the download, which happens only on click.

## Review focus

1. **A translocated launch** from Downloads: Move must find the original, copy it, and Trash only the original.
2. **Launch from inside the mounted DMG:** Move copies from the read-only volume and leaves the DMG alone.
3. **Network loss or a bad checksum mid-update:** the installed app is unchanged, temp files are removed, and the message says to try again.
4. **A release asset signed by another team or ad-hoc:** the update is refused with a clear message.
5. **A standard account** (no write access to /Applications): neither Move nor Update tries anything; both explain why.

## Left to the builder

- Exact card wording beyond the strings above, layout and icons.
- Whether the Move card also shows in the menu window or only on the dashboard. The dashboard is required.
- How the site's copy button looks.

## On-device checks before merge

- DMG: download-style quarantine → drag → Open Anyway → opens.
- Move to Applications, from both a translocated copy and the DMG.
- The Set 80% card sets the limit without the helper.
- "Install helper and apply" for 70%.
- Update now, against an `STB_RELEASE_FEED` pointing at a locally built newer version (for example 0.2.1), signed with the team.
- After the update, there is no quarantine flag and no prompt, and the helper still answers.

## Changes after on-device testing (2026-10-31)

- **The DMG stays unsigned.** Gatekeeper refuses to open a signed but unnotarized disk image downloaded in a browser. An unsigned image mounts, and only the signed app inside is checked.
- **Move drops the quarantine flag** from the copy instead of keeping it. With the flag, macOS would run the moved copy from a random App Translocation path again. The user already chose to run this app, so this weakens nothing they did not approve.
- **Move also asks at launch.** The dashboard card was missed on the device (it was scrolled out of view), so a copy outside Applications now shows an alert at launch; the card stays for "Not now".
- **The password dialog text is set by macOS.** It names the app ("'Save the Battery' … administrator access") and does not show the `with prompt` text on macOS 27.

