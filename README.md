# VibeBattery

Free, open-source macOS battery care and terminal coding-session companion.

**Status: in development.** Targets Apple Silicon; first validation target is M4 Pro on macOS 27.0.1. Hardware controls are capability-gated and will never be presented as working without verification.

- Battery health and power monitoring
- Display sleep while registered terminal jobs keep running
- Explicitly scoped cleanup of temporary task resources
- User-selectable energy settings

Design and implementation plan live in `docs/superpowers/`. No telemetry or cloud account is required.
