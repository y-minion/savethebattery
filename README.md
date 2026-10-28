**English** · [한국어](README.ko.md)

# VibeBattery

**A laptop's lifespan is decided by its battery. VibeBattery keeps yours healthy for longer — and features other apps charge for are all free here.**

Free and open source (MIT). A macOS menu bar app for battery care, with helpers for long terminal coding sessions.

![The VibeBattery menu window](docs/images/menu-window.gif)

```sh
curl -fsSL https://github.com/y-minion/vibebattery/releases/latest/download/install.sh | sh
```

**First thing: set the limit to 80% (Apple silicon, macOS 26.4 or later).** Open the menu window and pick 80% as the charge limit. macOS then stops charging there, even when VibeBattery is not running.

This is a beta (0.2.0). It has been tested on one Mac so far (an M4 Pro with macOS 27.0.1). Please [report problems](https://github.com/y-minion/vibebattery/issues).

## Why a charge limit helps

Lithium-ion cells age faster when they sit at a high charge, and faster still when they are also warm. Apple documents a Charge Limit for this reason ([support.apple.com/102338](https://support.apple.com/102338)), and Battery University explains the stress curve ([BU-808](https://batteryuniversity.com/article/bu-808-how-to-prolong-lithium-based-batteries)). VibeBattery does not promise a number of months or years. It shows what it measured on your Mac: hours spent at 90% and 95% or more, hours spent at 35 °C and 40 °C or more, cycles, and the capacity-based health estimate. The "if the limit had been 80%" comparison is a relative stress index from general Li-ion data, never a lifespan.

## Features other apps charge for — all free here

- **Menu bar status icon** that shows charging, paused at the limit and heat hold, as icon and percent, icon only, or percent only.
- **Customizable menu window:** choose which sections show and in what order.
- **Power flow:** adapter input, battery power and what the Mac itself uses. Values it cannot read are hidden, not guessed.
- **Hardware battery percentage** next to the macOS percentage.
- **Charge limit** from 50% to 100% (below 80% needs the optional helper), plus **schedules** by weekday and time.
- **One-time full charge**, then your limit comes back.
- **Heat hold:** pauses charging when the battery is hot (optional, while the app runs).
- **Low Power Mode switch** and **MagSafe LED modes** (macOS default, off, or by state). Both need the optional helper.
- **Health history and measured facts:** daily records on your Mac only, hours at high charge and heat compared with the previous period, cycles, a capacity-based health estimate, sleep drain and suggestions. `vbctl health --json` prints them.
- **Vibe-coding terminal sessions:** wrap `claude`, `codex` or any command with `vbctl run` to keep the Mac awake while it works, with a time limit and screen-off option.
- **Shortcuts actions:** set the limit, start and end a full charge, turn the limit off, set Low Power Mode, read the battery status.
- **Notifications** for each event you choose, once per situation.
- **English and Korean UI.** It follows your macOS language.

## Requirements

| Your Mac | Charge limit, schedules, full charge, heat hold, Low Power Mode, MagSafe LED | Everything else |
|---|---|---|
| Apple silicon, macOS 26.4 or later | Yes | Yes |
| Apple silicon, macOS 15 to 26.3 | After updating macOS to 26.4 | Yes |
| Intel, macOS 15 or later | Not supported | Yes |

The app is a universal build. On an Apple silicon Mac with an older macOS, a free macOS update to 26.4 or later turns on charge limiting. Intel Macs get everything except the charge features. The details are in [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) and [docs/VALIDATION.md](docs/VALIDATION.md).

## Install

### Terminal (no prompt)

```sh
curl -fsSL https://github.com/y-minion/vibebattery/releases/latest/download/install.sh | sh
```

The script checks your macOS version, downloads `VibeBattery.zip` and its checksum from the same release, verifies the SHA-256 and copies the app to `/Applications` without sudo. Files fetched with `curl` carry no quarantine flag, so macOS shows no Gatekeeper prompt. The app is not notarized (that needs the paid Apple program), so read the script before you pipe it to `sh`: [scripts/install.sh](scripts/install.sh).

### Browser download

1. Download `VibeBattery.zip` from the [latest release](https://github.com/y-minion/vibebattery/releases/latest), unzip it and move `VibeBattery.app` to `/Applications`.
2. Open it once. macOS says it cannot verify the app.
3. Open **System Settings › Privacy & Security**, scroll down and click **Open Anyway** next to VibeBattery, then confirm.

![Open Anyway in Privacy & Security](docs/images/open-anyway.png)

You do this once. The app is signed with a free Apple Development certificate, so the signature is valid; it is just not notarized.

## Safety

- VibeBattery changes nothing while AlDente, batt, battery or Battery Toolkit is installed or running. Two charge managers fighting over the same setting is a bad idea, so quit and remove the other one first.
- The charge limit is the macOS one. It stays in force when you quit the app, sleep or reboot, and you can see it in System Settings.
- The app logs the last 20 charge-setting writes it tried (time, command, who asked) in `charge.json`.
- Only the MagSafe LED key is ever written to the SMC. No charging SMC key is written.

## The optional helper

A limit of 80% or more, schedules and the one-time full charge need no extra rights. Limits below 80%, the Low Power Mode switch and the MagSafe LED need a small root helper. The app installs it from its own screen with the standard macOS administrator-password dialog, and only if you choose such a feature. It is never installed silently.

- It accepts only fixed requests: write a limit, read state, read version, switch Low Power Mode, set the LED to one of four values. It runs no shell and writes one SMC key (`ACLC`, values 0, 1, 3, 4).
- It serves only `/Applications/VibeBattery.app`, run by the logged-in user, and official builds are pinned to the signing team `JQWWU7443A`. A self-built (ad-hoc) copy is not team-pinned, and says so.
- The protocol is version 3. If you installed the helper with 0.1.x, install it again from the app once.

More in [SECURITY.md](SECURITY.md).

## Uninstall

```sh
curl -fsSL https://github.com/y-minion/vibebattery/releases/latest/download/uninstall.sh | sh
```

It removes the app and, with the macOS password dialog, the helper (the MagSafe LED goes back to macOS). It asks before it deletes your history and settings (kept by default). If the app is running, it also asks whether to turn off the macOS charge limit (kept by default); otherwise the limit stays as it is, and you can change it in System Settings › Battery. Source: [scripts/uninstall.sh](scripts/uninstall.sh).

## Build from source

You need Xcode. The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen); run `xcodegen generate` after changing it.

```sh
swift test --disable-xctest
python3 scripts/smoke-sessions.py .build/debug/vbctl
scripts/build-app.sh
open dist/VibeBattery.app
```

`scripts/build-app.sh` signs with an "Apple Development" certificate from your keychain (or the one named in `VB_SIGN_IDENTITY`). Without one it signs ad-hoc: the app works, but the Shortcuts app will not list its actions, and the helper will not be team-pinned (a self-built copy). See [CONTRIBUTING.md](CONTRIBUTING.md).

## Command line

The app must be running. `vbctl` asks it to apply charge settings over a same-user local channel.

```sh
VB=/Applications/VibeBattery.app/Contents/MacOS/vbctl
$VB charge set 70          # 50 to 100, steps of 5
$VB charge off             # turn the limit off
$VB charge topup           # one-time full charge
$VB charge end             # end the full charge
$VB charge status --json   # also works without the app
$VB health --json
$VB run --hours 4 --screen-off -- claude
```

Exit codes: 0 success, 1 failed or unverified, 2 usage error, 3 app not running. A session's idle-sleep protection ends after its time or when the adapter is unplugged; the command itself is never killed.

## Privacy

There is no telemetry and no account. History and sessions are stored only in `~/Library/Application Support/VibeBattery`. The one network request is a daily check of `api.github.com` for a new version, with no identifying data; you can turn it off in Settings. Network failures are silent, and nothing is installed automatically.

## More

Design notes and plans live in [docs/superpowers](docs/superpowers). Release notes: [docs/release-notes/0.2.0.md](docs/release-notes/0.2.0.md).

MIT · [License](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md)
