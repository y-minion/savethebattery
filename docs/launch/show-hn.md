<!-- Show HN draft (English). Post it yourself; be around to answer comments. Link the repo as the URL. -->

**Title:** Show HN: VibeBattery – free, open-source macOS battery care that shows measured facts

**URL:** https://github.com/y-minion/vibebattery

**First comment:**

Hi HN. A laptop's lifespan is mostly decided by its battery, and a charge limit helps because lithium-ion cells age faster when they sit at high charge and heat (Apple documents a Charge Limit, support.apple.com/102338; Battery University BU-808 covers the stress curve). I built VibeBattery, a menu bar app that drives the macOS charge limit and adds the things I wanted around it: schedules, a one-time full charge, heat hold, power flow, Low Power Mode and MagSafe LED control, Shortcuts actions, and English and Korean UI. All of it is free, MIT, no telemetry.

I did not want to claim "adds N years". The app shows what it measured on your Mac: hours at 90/95% and above, hours at 35/40 C and above, cycles, and a capacity-based health estimate, compared with the previous period. The "if the limit had been 80%" figure is a relative stress index from general Li-ion data, not a lifespan.

Things worth knowing:
- Beta 0.2.0. I have verified it by hand on one Mac (M4 Pro, macOS 27.0.1). CI builds and runs read-only checks on macOS 15.
- The charge limit works on Apple silicon with macOS 26.4+; older Apple silicon Macs can update macOS for free. Intel Macs (universal build) get everything else; charge limiting there is not supported.
- I do not pay for the Apple Developer Program, so it is signed with a free development certificate and not notarized. The curl installer verifies SHA-256 and installs without sudo; curl downloads carry no quarantine flag, so there is no Gatekeeper prompt. The script is short, please read it.
- The optional root helper (for limits below 80%, Low Power Mode and the LED) is installed from the app via the admin-password dialog. It takes fixed requests only, writes one SMC key (ACLC, the MagSafe LED), runs no shell, and official builds are pinned to the signing team. Details in SECURITY.md.
- The only network request is a daily GitHub releases check, which can be switched off.

I would like feedback on the helper's attack surface and on what you would want measured.

```
curl -fsSL https://github.com/y-minion/vibebattery/releases/latest/download/install.sh | sh
```

https://github.com/y-minion/vibebattery
