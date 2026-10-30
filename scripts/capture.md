# Captures for the README, site and posts

The owner records these on their own Mac and saves them under `docs/images/`. In use now: `menu-window.png`, `menu-window.ko.png` and `open-anyway.ko.png` (the English README describes Open Anyway in text, because System Settings could not be switched to English for one app). The other rows are for the site and posts. Record each shot in English (macOS set to English) and in Korean (macOS set to Korean, or launch with `STB_LANG=ko`), and keep personal data out of frame (account names, serial numbers).

| File | What to show |
|---|---|
| `menu-window.png` / `menu-window.ko.png` | The menu window, opened from the menu bar (⌘⇧4, Space, Option-click the window). A GIF needs ffmpeg or similar. |
| `dashboard-power-flow.png` / `.ko.png` | The dashboard power flow bar with the adapter connected. |
| `health-card.png` / `.ko.png` | The health card with the measured facts (hours at high charge and heat, cycles, estimate). |
| `settings-led.png` / `.ko.png` | Settings, MagSafe LED modes. |
| `open-anyway.ko.png` | System Settings › Privacy & Security with the "Open Anyway" button for Save the Battery, after opening the browser-downloaded app once, cropped to the Security section. |

## Commands

Window screenshots without shadow (click the window when the crosshair appears, or pass a window id):

```sh
screencapture -o -w docs/images/dashboard-power-flow.png        # interactive: click the window
WID=$(osascript -e 'tell application "System Events" to get id of window 1 of process "Save the Battery"')
screencapture -o -l "$WID" docs/images/health-card.png          # by window id
```

If the window id lookup does not work on your macOS, use the interactive `-w` form. A GIF can be recorded with `screencapture -v clip.mov` (stop with Control-C), then converted, for example with `ffmpeg -i clip.mov -vf "fps=12,scale=720:-1" docs/images/menu-window.gif` if you have ffmpeg. Repeat each shot with `STB_LANG=ko` (launch `STB_LANG=ko "/Applications/Save the Battery.app/Contents/MacOS/Save the Battery"`) for the `.ko` files.
