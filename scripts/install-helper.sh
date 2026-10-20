#!/bin/sh
# Installs VibeBattery's charge-limit helper as a root LaunchDaemon.
# Usage: sudo /Applications/VibeBattery.app/Contents/Resources/install-helper.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "관리자 권한이 필요합니다: sudo $0" >&2; exit 1; }
LABEL=io.github.y-minion.vibebattery.helper
APP=${1:-/Applications/VibeBattery.app}
SRC="$APP/Contents/MacOS/VBChargeHelper"
DEST=/Library/PrivilegedHelperTools/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist
[ "$APP" = /Applications/VibeBattery.app ] || echo "주의: 헬퍼는 /Applications/VibeBattery.app의 요청만 받습니다." >&2
codesign --verify --strict "$APP"
install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
# Copy first, then check the root-owned copy, so the bundle cannot change between check and install.
TMP=$(mktemp /Library/PrivilegedHelperTools/.vbhelper.XXXXXX)
trap 'rm -f "$TMP"' EXIT
install -o root -g wheel -m 755 "$SRC" "$TMP"
codesign --verify --strict "$TMP"
codesign -dv "$TMP" 2>&1 | grep -q "^Identifier=$LABEL\$" || { echo "헬퍼 서명 식별자가 다릅니다." >&2; exit 1; }
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
echo "설치했습니다: $LABEL"
