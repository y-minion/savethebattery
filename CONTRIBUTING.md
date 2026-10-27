# Contributing

Thanks for helping. VibeBattery is free and stays free; the goal is a battery app people can trust, so honest copy and safe behaviour matter more than new features.

## Build and test

You need Xcode (the repo builds with Xcode 27.x and the Swift 6.4 toolchain, Swift 5 language mode).

```sh
swift build
swift test --disable-xctest        # about 244 tests, Swift Testing
python3 scripts/smoke-sessions.py .build/debug/vbctl
scripts/build-app.sh               # builds dist/VibeBattery.app and dist/VibeBattery.zip
```

The Xcode project is generated from `project.yml` with XcodeGen. After changing `project.yml` or adding files to the app or tool targets, run `xcodegen generate` and commit `VibeBattery.xcodeproj`.

## Self-built copies and the helper

`scripts/build-app.sh` signs with an "Apple Development" certificate from your keychain, or the one in `VB_SIGN_IDENTITY`. Without one it signs ad-hoc. An ad-hoc app works, but Shortcuts will not list its actions, and the root helper is not team-pinned: official builds pin the helper to team `JQWWU7443A`, and your build cannot match it. A self-built helper accepts the identifier-only rule; it logs a "self-built (ad-hoc), not team-pinned" line, and the app shows a self-built note on the helper card. Do not expect an official helper to accept your build, or the other way round. Never commit a certificate or `dev.pem`.

## Rules for changes

- English is the base language and Korean the translation. UI text goes through `tr(en, ko)`; Hangul literals in Swift sources are allowed only inside `tr(...)`.
- Public copy states measured facts or cited research, never a lifespan number. It does not name other apps, except in the conflict-safety lists.
- The only network request is the version check. No telemetry.
- Keep the helper's allow-list small. A new helper request needs a clear reason and a test.

## Pull requests

1. Fork, then branch from `main`.
2. Make a focused change with tests where there is logic.
3. Run `swift test --disable-xctest` and `swift build`; CI runs them too.
4. Open a PR that says what changed and how you checked it. Mention the Mac and macOS version if you tested on a device.
