#!/bin/sh
# Installs Save the Battery's charge-limit helper as a root LaunchDaemon.
# Usage: sudo "/Applications/Save the Battery.app/Contents/Resources/install-helper.sh"
set -eu
stb_lang() { case "${STB_LANG:-$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2s/[^a-z]*\([a-z]*\).*/\1/p')}" in ko*) echo ko;; *) echo en;; esac; }
msg() { if [ "$(stb_lang)" = ko ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }
[ "$(id -u)" = 0 ] || { msg "Administrator rights are required: sudo $0" "관리자 권한이 필요합니다: sudo $0" >&2; exit 1; }
LABEL=io.github.y-minion.savethebattery.helper
APP="${1:-/Applications/Save the Battery.app}"
SRC="$APP/Contents/MacOS/STBChargeHelper"
DEST=/Library/PrivilegedHelperTools/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist
[ "$APP" = "/Applications/Save the Battery.app" ] || msg "Note: the helper only accepts requests from /Applications/Save the Battery.app." "주의: 헬퍼는 /Applications/Save the Battery.app의 요청만 받습니다." >&2
codesign --verify --strict "$APP"
install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
# Copy first, then check the root-owned copy, so the bundle cannot change between check and install.
TMP=$(mktemp /Library/PrivilegedHelperTools/.stbhelper.XXXXXX)
trap 'rm -f "$TMP"' EXIT
install -o root -g wheel -m 755 "$SRC" "$TMP"
codesign --verify --strict "$TMP"
codesign -dv "$TMP" 2>&1 | grep -q "^Identifier=$LABEL\$" || { msg "The helper signing identifier does not match." "헬퍼 서명 식별자가 다릅니다." >&2; exit 1; }
launchctl bootout "system/$LABEL" 2>/dev/null || true
mv -f "$TMP" "$DEST"
trap - EXIT
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array><string>$DEST</string></array>
<key>MachServices</key><dict><key>$LABEL</key><true/></dict>
</dict></plist>
EOF
chown root:wheel "$PLIST";chmod 644 "$PLIST"
launchctl bootstrap system "$PLIST"
msg "Installed: $LABEL" "설치했습니다: $LABEL"
