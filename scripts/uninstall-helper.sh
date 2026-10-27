#!/bin/sh
# Removes the helper. The current charge limit is left as it is.
set -eu
vb_lang() { case "${VB_LANG:-$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2s/[^a-z]*\([a-z]*\).*/\1/p')}" in ko*) echo ko;; *) echo en;; esac; }
msg() { if [ "$(vb_lang)" = ko ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }
[ "$(id -u)" = 0 ] || { msg "Administrator rights are required: sudo $0" "관리자 권한이 필요합니다: sudo $0" >&2; exit 1; }
LABEL=io.github.y-minion.vibebattery.helper
DEST=/Library/PrivilegedHelperTools/$LABEL
# Hand the MagSafe LED back to macOS. A version 1 helper ignores arguments and keeps
# running, so the wait is bounded.
if [ -x "$DEST" ]; then
    "$DEST" --led system & LED=$!
    ( sleep 5; kill "$LED" 2>/dev/null ) & WATCH=$!
    wait "$LED" || true
    kill "$WATCH" 2>/dev/null || true
fi
launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/$LABEL.plist" "$DEST"
msg "Helper removed. The current charge limit stays as it is. Use macOS battery settings to change it." "헬퍼를 제거했습니다. 현재 충전 상한은 그대로 유지됩니다. 바꾸려면 macOS 배터리 설정을 사용하세요."
