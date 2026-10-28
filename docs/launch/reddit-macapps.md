<!-- r/macapps draft (English). Check the subreddit's current self-promotion and flair rules before posting; post it yourself. -->

**Title:** VibeBattery: a free, open-source battery care app for the menu bar (charge limit, schedules, health facts), everything free

**Body:**

I wanted a battery app that keeps my MacBook healthy and does not hold features back behind a paywall, so I built one and open-sourced it (MIT). Everything in it is free.

What it does:
- Charge limit 50 to 100%, weekday schedules, one-time full charge, heat hold
- Live menu bar status icon and a customizable menu window
- Power flow (adapter in, battery, what the Mac uses) and the hardware battery percentage
- Low Power Mode switch and MagSafe LED modes
- Health history with measured facts: hours at 90/95% and above, hours at 35/40 C and above, cycles, a capacity-based health estimate
- Shortcuts actions and notifications; English and Korean UI
- Terminal sessions (`vbctl run`) that keep the Mac awake while a coding agent runs

What it deliberately does not do: promise months or years of extra life. A lithium-ion battery ages faster at high charge and heat (Apple's Charge Limit article and Battery University BU-808 explain why), so the app shows what it actually measured on your Mac and nothing more. No telemetry; the only network request is a daily version check you can turn off.

Honest limits:
- 0.2.0 is a beta. I have tested it by hand on one Mac so far (M4 Pro, macOS 27.0.1).
- The charge limit needs Apple silicon and macOS 26.4+ (older Apple silicon Macs can update macOS for free). Intel Macs get everything except charge limiting.
- It is signed with a free Apple Development certificate and is not notarized. The terminal install opens without a prompt; a browser download needs System Settings > Privacy & Security > Open Anyway once.
- Limits below 80%, Low Power Mode and the LED need an optional root helper, installed from the app with the admin-password dialog. It accepts fixed requests only and writes one SMC key (the MagSafe LED).

First thing after installing: set the limit to 80% (Apple silicon, macOS 26.4 or later).

Install (the script is in the repo, read it first):

```
curl -fsSL https://github.com/y-minion/vibebattery/releases/latest/download/install.sh | sh
```

Repo: https://github.com/y-minion/vibebattery

Bug reports and feedback very welcome.
