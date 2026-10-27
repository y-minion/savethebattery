#!/bin/sh
# Removes VibeBattery: optionally clears the charge limit, removes the helper and the app, and optionally the data.
# curl -fsSL https://github.com/y-minion/vibebattery/releases/latest/download/uninstall.sh | sh
set -eu
vb_lang() { case "${VB_LANG:-$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2s/[^a-z]*\([a-z]*\).*/\1/p')}" in ko*) echo ko;; *) echo en;; esac; }
msg() { if [ "$(vb_lang)" = ko ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }
# Answers come from the terminal so this also works when piped from curl.
ask() { printf '%s ' "$1" >/dev/tty; read -r ANSWER </dev/tty || ANSWER=n; case "$ANSWER" in y|Y|yes|YES) return 0;; *) return 1;; esac; }
main() {
APP=/Applications/VibeBattery.app
LABEL=io.github.y-minion.vibebattery.helper
if pgrep -x VibeBattery >/dev/null 2>&1; then
    if ask "$(msg "Turn off the macOS charge limit too? [y/N]" "macOS 충전 상한도 해제할까요? [y/N]")"; then
        "$APP/Contents/MacOS/vbctl" charge off || msg "Could not turn off the charge limit." "충전 상한을 해제하지 못했습니다." >&2
    fi
else
    msg "The macOS charge limit stays as it is; change it in System Settings › Battery." "macOS 충전 상한은 그대로 유지됩니다. 시스템 설정 › 배터리에서 바꿀 수 있습니다."
fi
# The app hands the MagSafe LED back to macOS when it quits; wait for it before the helper goes.
osascript -e 'quit app "VibeBattery"' >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x VibeBattery >/dev/null 2>&1 || break; sleep 1; done
if [ -e "/Library/LaunchDaemons/$LABEL.plist" ]; then
    msg "Removing the helper (an administrator password is requested)." "헬퍼를 제거합니다 (관리자 암호를 요청합니다)."
    if [ -f "$APP/Contents/Resources/uninstall-helper.sh" ]; then
        CMD="/bin/sh '$APP/Contents/Resources/uninstall-helper.sh'"
    else
        H=/Library/PrivilegedHelperTools/$LABEL
        CMD="if [ -x $H ]; then $H --led system >/dev/null 2>&1 & P=\$!; ( sleep 5; kill \$P ) >/dev/null 2>&1 & W=\$!; wait \$P; kill \$W; fi; /bin/launchctl bootout system/$LABEL; /bin/rm -f /Library/LaunchDaemons/$LABEL.plist $H; true"
    fi
    osascript -e "do shell script \"$CMD\" with administrator privileges" || msg "The helper was not removed." "헬퍼를 제거하지 못했습니다." >&2
fi
if [ -e "$APP" ]; then
    rm -rf "$APP"
    msg "Removed $APP" "$APP 을 제거했습니다."
fi
if ask "$(msg "Delete VibeBattery data (history, settings)? [y/N]" "VibeBattery 데이터(기록, 설정)를 삭제할까요? [y/N]")"; then
    rm -rf ~/Library/Application\ Support/VibeBattery
    defaults delete io.github.y-minion.vibebattery 2>/dev/null || true
    msg "Data deleted." "데이터를 삭제했습니다."
fi
}
main "$@"
