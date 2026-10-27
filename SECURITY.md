# Security

## What the root helper can do

VibeBattery is a normal app. Only the optional helper runs as root, and it exists for three features: charge limits below 80%, the Low Power Mode switch and the MagSafe LED. The app installs it from inside its own screen through the macOS administrator-password dialog, and never without being asked.

- **Fixed requests only.** The helper (protocol version 3) answers a short list: write a charge limit (50 to 100), read state, read version, switch Low Power Mode on or off, and set the MagSafe LED to one of four modes.
- **One SMC key.** The only SMC write is `ACLC` (the MagSafe LED), with the values 0, 1, 3 and 4. No charging SMC key is ever written.
- **No shell.** It runs no shell and executes no command text from the client. Low Power Mode is switched with a fixed `pmset` call.
- **Who may call it.** The caller must be the logged-in console user, run from `/Applications/VibeBattery.app`, and carry the app's signing identifier. Official builds are also pinned to the signing team `JQWWU7443A` (`anchor apple generic and certificate leaf[subject.OU] = "JQWWU7443A"`). The app applies the same requirement to the helper.
- **Self-built copies.** Builds without a team (ad-hoc, for CI or if you build from source) keep the identifier-only rule: the helper logs "self-built (ad-hoc), not team-pinned" (an NSLog line), and the app shows a self-built note on the helper card. If a process cannot read its own signature, it does not fall back to that rule: the helper exits, and the app accepts no helper. Only root can replace an installed helper, so a self-built helper is your own choice.

The app is signed with a free Apple Development certificate and is not notarized. The installer script and the release checksum are the way to check what you run: `scripts/install.sh` verifies SHA-256 before it touches `/Applications`.

## Network and data

No telemetry. The one network request is the daily version check, `GET https://api.github.com/repos/y-minion/vibebattery/releases/latest`, with no identifying data. History stays on your Mac.

## Reporting a problem

Please report a vulnerability privately with GitHub's private vulnerability reporting: open the repository's **Security** tab and choose **Report a vulnerability** (https://github.com/y-minion/vibebattery/security/advisories/new). Do not put it in a public issue. This is a small free project run by one person, so expect a reply in days, not hours.
