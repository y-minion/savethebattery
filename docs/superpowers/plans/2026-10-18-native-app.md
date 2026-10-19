# VibeBattery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an executable native app and terminal companion, validate real hardware capabilities, and publish the source to GitHub.
**Architecture:** A dependency-free Swift package separates pure safety policies, macOS adapters, terminal supervisors, and SwiftUI presentation. User-owned local files communicate session status; processes are only terminated by the supervisor that launched them. Charging controls remain unavailable unless a verified backend exists.
**Tech Stack:** Swift 6 in Swift 5 language mode, macOS 15+, SwiftUI/AppKit, IOKit, a small C bridge for libproc/SMC, Foundation, Swift Testing.
**Spec:** ../specs/2026-10-18-design.md

## Global Constraints
- First validation target: M4 Pro, macOS 27.0.1 (26A434).
- All delivered functionality is free and source is public; no telemetry, account, or private machine samples in Git.
- No automatic forced discharge, calibration, global process kill, or security-protection bypass.
- Unknown sensor/control data must remain unknown; a settings link is not direct charging control.
- Mode choice belongs to the user. Process cleanup defaults to observation.
- Existing conversations/terminal jobs must not be used as destructive test subjects.
- User approved design and implementation plus GitHub publication. Execute continuously with independent final review.

## Review Focus
- PID reuse or tampered session metadata must never terminate an unrelated process (Tasks 2/3).
- Interactive CLI input wait is not completion; expired protection is not cancellation (Task 3).
- AC disconnect, concurrent sessions, interrupted supervisors must release only owned power assertions (Tasks 2/3).
- Missing temperature or capacity cannot become a plausible zero or synthetic health (Tasks 1/2).
- Restoring a setting must not overwrite an intervening user change; unverified hardware capability stays disabled (Tasks 1/4).

---

### Task 1: Core models and policies
**Files:** Package.swift; Sources/BatteryCore/BatterySnapshot.swift; Sources/BatteryCore/ChargePolicy.swift; Sources/BatteryCore/SessionPolicy.swift; Tests/BatteryCoreTests/PolicyTests.swift.
**Interfaces:** BatterySnapshot.decode([String:Any], now: Date) -> BatterySnapshot; ChargePolicy.decide(snapshot:settings:previous:) -> ChargeDecision; SessionPolicy.cleanupAllowed(outcome:registered:shared:policy:) -> Bool.
- [ ] Add package and failing behavior tests for missing sensors, signed current, capacity units, charge hysteresis, heat hold, stale sensors, observation/failed/protected session cleanup.
- [ ] Run `swift test`; observe assertions fail against minimal stubs.
- [ ] Implement policies; no hardware mutations.
- [ ] Run `swift test`; expect all green. Commit.

### Task 2: macOS reads and scoped effects
**Files:** Sources/MacBridge/{include/MacBridge.h,MacBridge.c}; Sources/BatteryPlatform/{BatteryReader,ProcessReader,PowerLease,HistoryStore}.swift; Tests/BatteryCoreTests/PlatformTests.swift.
**Interfaces:** BatteryReader.read() -> BatterySnapshot; ProcessReader.snapshot() -> [ProcessSample]; PowerLease.acquire/release; HistoryStore.append/read/delete; ProcessIdentity.matches(current:).
- [ ] Write failing tests for PID start-time mismatch, same-user restrictions, history retention/corruption, snapshot fallback behavior.
- [ ] Implement public power-source reads plus IORegistry; read-only SMC temperature probes; safe metadata-only libproc snapshots; scoped IOPM sleep assertions.
- [ ] Verify tests and compare live battery readings with system-reported values. Record unavailable controls/sensors without writes. Commit.

### Task 3: Terminal sessions and temporary resources
**Files:** Sources/VibeCLI/{Main,SessionRunner,ResourceRunner}.swift; Sources/BatteryPlatform/SessionStore.swift; Tests/BatteryCoreTests/SessionTests.swift; scripts/smoke-sessions.sh.
**Interfaces:** `vbctl status [--json]`; `run [--hours N] [--screen-off] [--cleanup] -- command args`; `resource [--keep] -- command args` (requires managed session); `sessions`; `release ID`.
- [ ] Write failing tests for argument validation, exit status, release without kill, timeout without cleanup, success-only cleanup, concurrent-session files and redacted metadata.
- [ ] Implement run with inherited terminal IO and child exit propagation, per-session bounded sleep lease, AC disconnect handling, owner-only files.
- [ ] Implement explicit resource registration and supervisor-owned graceful termination. No arbitrary PID termination from a session file. Unknown/background descendants are observation-only.
- [ ] Run unit tests and controlled real subprocess smoke tests, including failure preservation and command names with spaces. Commit.

### Task 4: Native desktop and menu bar
**Files:** Sources/VibeBattery/{App,AppModel,DashboardView,ProcessesView,SessionsView,SettingsView}.swift; Sources/BatteryPlatform/SettingsStore.swift.
**Interfaces:** Dashboard consumes BatteryReader/history; process UI consumes ProcessReader; sessions consumes SessionStore; persisted Settings controls polling/cleanup/presentation.
- [ ] Write failing tests for settings validation and process-action eligibility (PID identity checked immediately before action).
- [ ] Implement Korean native dashboard, history, source-aware readings, selected process normal/force termination with explicit confirmation, sessions, user preferences, menu bar.
- [ ] Expose only verified controls; explain native Battery settings handoff and unavailable sailing/heat/calibration/LED controls. Provide CLI setup guidance and a copyable correctly shell-quoted command.
- [ ] Build app, inspect it in the UI, and verify visible real state matches readings. Commit.

### Task 5: Capability report and distribution
**Files:** scripts/build-app.sh; .github/workflows/ci.yml; LICENSE; THIRD_PARTY_NOTICES.md; docs/COMPATIBILITY.md; README.md.
**Interfaces:** `scripts/build-app.sh` produces an ad-hoc signed .app with embedded CLI; CI builds/tests on macOS.
- [ ] Verify unresolved charge/temperature access through read-only source/runtime investigation. Do not claim gated features implemented.
- [ ] Add reproducible build, MIT license for original code, notices for any reused implementation, README and exact supported/partial/unavailable feature matrix.
- [ ] Run complete tests, release build, CLI smoke tests and app launch validation. Review tracked files for secrets/private samples.
- [ ] Perform fresh independent code review; fix material findings with regression tests, push development branch, create PR, and attach it to the task.
- [ ] Provide local app, repository and PR with tested behavior and remaining hardware limitations.

## Coverage / decisions
- Monitoring, scoped process actions, energy settings handoff, history, display sleep and session cleanup are directly implemented by Tasks 1–4.
- Charge limit/sailing/heat/calibration/sleep/LED are evaluated in Tasks 2/5; unsupported writes are intentionally not simulated. Their unmet requirements remain explicit in the report.
- Scheduling/Shortcuts only expose executable capabilities; advanced hardware automation follows verified backend support. Initial version documents these deferred requirements rather than shipping nonfunctional switches.
- Use this dedicated new repository on a feature branch as the isolated workspace; there is no pre-existing user code to protect with another checkout.
