#!/bin/sh
# Removes the helper. The current charge limit is left as it is.
set -eu
[ "$(id -u)" = 0 ] || { echo "관리자 권한이 필요합니다: sudo $0" >&2; exit 1; }
LABEL=io.github.y-minion.vibebattery.helper
launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/$LABEL.plist" "/Library/PrivilegedHelperTools/$LABEL"
echo "헬퍼를 제거했습니다. 현재 충전 상한은 그대로 유지됩니다. 바꾸려면 macOS 배터리 설정을 사용하세요."
