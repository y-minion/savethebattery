# Validation — development preview 0.1

Validated on the initial M4 Pro / macOS 27.0.1 target and a GitHub macOS runner.

- 17 Swift Testing tests cover sensor decoding, charging decision policies, ownership guards, settings, history, and inactive-session retention. Charging policies are pure models; this does not validate hardware charging writes.
- Disposable-process integration checks cover literal arguments, exit codes, expiry before completion, release without command cancellation, cancellation of a signal-ignoring child, concurrent power assertions, registered resource cleanup, failed-session preservation, and `--keep`.
- Power-assertion checks inspect the operating system's assertion list for the two test supervisor PIDs. Releasing one leaves the other intact.
- The same integration suite runs against the CLI embedded in the release app, after both executables have been built. Their distinct names (`VibeBattery` and `vbctl`) also work on case-insensitive filesystems.
- An interactive pseudo-terminal check confirmed that input reaches the wrapped command and the resulting exit status is preserved.
- The native dashboard, process list, session controls, and settings were inspected. Live readings and the embedded CLI were checked on the target Mac.
- The bundle is locally ad-hoc signed; the build also creates an archive without Finder presentation metadata.

The independent review found PID-reuse risk in arbitrary raw signals, delayed assertion release after cancellation, and expiry/completion ordering. Raw signals now target only unreaped direct children; selected ordinary apps use AppKit application-instance termination. Cancellation releases the lease immediately, and expiry/release is processed before successful completion. Regression checks reproduce the original signal-ownership and expiry failures and pass with the fixes.

## Charge control (2026-10-20)

- 51 Swift Testing tests now pass, adding charge-command ranges, limit origin, read-back matching, heat-hold hysteresis (5-minute stable resume, stale and missing temperature, low charge, missing helper, external change during a hold), 5% limit steps, conflict detection (including a leftover AlDente daemon and excluding VibeBattery's own helper), controller routing and read-back failure, persistence across restarts, pausing after a failed automatic write or an external change, keeping the hold when a restore fails, refusing top-up during a hold, restoring on app quit, legacy preference files, and helper client authorization.
- The PowerUI bridge rejects out-of-range limits before calling macOS; tests never pass a valid limit, so automated runs do not change the real charge limit.
- On the target Mac, `vbctl charge status` reported the same limit as `pmset -g battlimit` (79%) and detected the running AlDente; the rebuilt app launched with writes blocked and left the limit unchanged.
- The release bundle embeds `VBChargeHelper` signed with identifier `io.github.y-minion.vibebattery.helper` and the install/uninstall scripts; both scripts refuse to run without root.
- Pending (requires the user at the Mac after removing AlDente): helper installation, 80–100% and sub-80 writes, one-time full charge and its return, persistence across app quit, sleep and reboot.

Not claimed as validated: hardware charge-limit writes, real high-temperature heat hold, physical display behavior across external monitors, lid-close/background automation compatibility, manual termination of the user's apps, or support across other hardware/OS combinations. See [the capability report](COMPATIBILITY.md) for unimplemented features.
