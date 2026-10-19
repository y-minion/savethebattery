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
| Charge cap / power modes | Opens macOS Battery settings. Direct app control not implemented or claimed |
| Sailing / heat charging pause / calibration / MagSafe LED | Not available: no verified charging write backend in this release |
| Schedules / Shortcuts / one-time full charge | Not implemented; native settings may provide related functionality |
| One-year health history / sleep drain diagnostics / automatic AI turn hooks | Planned, not implemented |

## Scope and safeguards

A registered command ending is the completion signal. An interactive AI tool awaiting another prompt is still running. Existing jobs are not retroactively adopted for automatic cleanup. Use `resource --keep` for a persistent server; if ownership or lifecycle is unknown it is left alone.

Protection expires after the selected duration or, by default, when AC is disconnected. This releases only VibeBattery's sleep assertion; the command is not killed, and macOS may subsequently sleep. `--allow-battery` is an explicit override of AC-only protection. OS low-battery, lid-close and explicit sleep are not overridden. Other apps or system settings can still prevent sleep after VibeBattery releases its own assertion.

The app UI quitting does not kill terminal-managed sessions; each CLI supervisor owns its assertion. A killed supervisor's assertion is released by macOS; any uncertain resource is left running. Closing the lid or locking the screen may interrupt screen-based automation. App Nap, authentication waits and network failures are not solved by holding the system awake.

The current app is ad-hoc signed for local testing and is not Developer ID notarized. No privilege helper, SMC write, security setting change, or cloud service is installed.
