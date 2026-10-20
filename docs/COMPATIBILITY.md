# Capability report

Target machine: Apple Silicon M4 Pro, macOS 27.0.1 (26A434). Other models and OS releases are not yet validated. Source supports macOS 15+ compilation, which is not a compatibility claim.

| Feature | Implementation / verification |
|---|---|
| Battery percentage, charge state, AC status, cycles | Implemented using AppleSmartBattery IORegistry reads; live target readings verified |
| Battery health | Capacity-based estimate, explicitly labelled; not remaining years or an exact match to Apple's displayed health |
| Battery temperature | AppleSmartBatteryPack BatteryData Temperature fallback verified on target; no CPU-temperature substitution |
| Battery power | Signed current × voltage; does not represent total adapter input power |
| Process activity | Same-user processes ranked by sampled CPU activity; not per-process watts |
| Selected application termination | Start time, UID and protected process guards; instance-bound NSRunningApplication normal/force requests require explicit selection. Bare workers are handed off to Activity Monitor |
| Seven-day battery history | Local, optional, deletable; missing data stays unknown |
| Session metadata | Inactive records pruned after 30 days on app refresh/session start; user-deletable; live supervisors preserved |
| Terminal sessions | Direct argv execution, inherited terminal IO, real exit status, scoped bounded idle-sleep assertion |
| Display sleep | Uses macOS display-sleep request; manual screen-off/physical-display test is separate from command success |
| Safe resource cleanup | Opt-in; only supervisor-created explicitly registered resource; success-only SIGTERM; no automatic SIGKILL |
| Charge limit 80–100% | macOS charge limit through the private PowerUI client; each write is verified by reading it back. Read path verified on target; hardware write validation pending (see VALIDATION.md) |
| Charge limit 50–79% | Optional root helper writing `com.apple.smartcharging.topoffprotection`; accepts only `setLimit(50…100)` and `readState`; clients must be the console user running `/Applications/VibeBattery.app` with the app's signing identifier (ad-hoc builds: identifier only, no team ID). Hardware validation pending |
| One-time full charge | PowerUI temporary disable; when the limit returns is decided by macOS. Hardware validation pending |
| Heat charging hold | Opt-in. At or above the hold temperature while charging and at ≥ 50%, lowers the limit to the current charge; restores only its own value after 5 minutes at or below the resume temperature. Works only while the app runs. Policy tested with injected temperatures; real high-temperature behavior not validated |
| Other charge managers | AlDente and batt are detected by running app or installed daemon; all writes and heat hold are blocked while present |
| Sailing lower bound / forced discharge / calibration | Not available: firmware 20457.1.29 blocks the SMC charge keys; the only remaining control is adapter cutoff, which conflicts with battery preservation |
| Power modes | Opens macOS Battery settings |
| MagSafe LED | Planned (`ACLC` readable, write unverified) |
| Schedules / Shortcuts / one-time full charge | Not implemented; native settings may provide related functionality |
| One-year health history / sleep drain diagnostics / automatic AI turn hooks | Planned, not implemented |

## Firmware findings (2026-10-20)

Read-only SMC probing on the target found no `CHTE`, `CH0B`, `CH0C` or `CH0I`; the firmware-limit keys `bfD0`/`bfE0`/`bfF0` refuse reads. `CHIE` (adapter cutoff) and `ACLC` (MagSafe LED) are readable. The macOS charge limit (`PowerUISmartChargeClient`) reports support and offers 80/85/90/95/100. Limits below 80 were observed (79%, set by AlDente) and appear to come from the root-owned `com.apple.smartcharging.topoffprotection` domain. Details: [charge control design](superpowers/specs/2026-10-20-charge-control-design.md).

## Scope and safeguards

A registered command ending is the completion signal. An interactive AI tool awaiting another prompt is still running. Existing jobs are not retroactively adopted for automatic cleanup. Use `resource --keep` for a persistent server; if ownership or lifecycle is unknown it is left alone.

Protection expires after the selected duration or, by default, when AC is disconnected. This releases only VibeBattery's sleep assertion; the command is not killed, and macOS may subsequently sleep. `--allow-battery` is an explicit override of AC-only protection. OS low-battery, lid-close and explicit sleep are not overridden. Other apps or system settings can still prevent sleep after VibeBattery releases its own assertion.

The app UI quitting does not kill terminal-managed sessions; each CLI supervisor owns its assertion. A killed supervisor's assertion is released by macOS; any uncertain resource is left running. Closing the lid or locking the screen may interrupt screen-based automation. App Nap, authentication waits and network failures are not solved by holding the system awake.

The current app is ad-hoc signed for local testing and is not Developer ID notarized. No SMC write, security setting change, or cloud service is installed. The optional charge helper is installed only when the user runs its install script with sudo, and is removed with the matching uninstall script.
