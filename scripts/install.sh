#!/bin/sh
# Installs the latest VibeBattery release into /Applications without sudo.
# curl -fsSL https://github.com/y-minion/vibebattery/releases/latest/download/install.sh | sh
# Test overrides: VB_RELEASE_BASE, VB_INSTALL_DIR, VB_SKIP_OPEN.
set -eu
vb_lang() { case "${VB_LANG:-$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2s/[^a-z]*\([a-z]*\).*/\1/p')}" in ko*) echo ko;; *) echo en;; esac; }
msg() { if [ "$(vb_lang)" = ko ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }
BASE=${VB_RELEASE_BASE:-https://github.com/y-minion/vibebattery/releases/latest/download}
DIR=${VB_INSTALL_DIR:-/Applications}
OS=$(sw_vers -productVersion); ARCH=$(uname -m)
[ "${OS%%.*}" -ge 15 ] || { msg "VibeBattery needs macOS 15 or later (this Mac runs $OS)." "VibeBattery는 macOS 15 이상이 필요합니다 (이 Mac은 $OS)." >&2; exit 1; }
if [ "$ARCH" = arm64 ] && [ "$(printf '%s\n26.4\n' "$OS" | sort -V | head -1)" = 26.4 ]; then
    msg "macOS $OS on $ARCH: everything is supported, including the charge limit." "macOS $OS ($ARCH): 충전 상한을 포함한 모든 기능을 지원합니다."
else
    msg "macOS $OS on $ARCH: supported, but the charge limit needs Apple silicon and macOS 26.4 or later." "macOS $OS ($ARCH): 사용할 수 있지만 충전 상한은 Apple 실리콘과 macOS 26.4 이상이 필요합니다."
fi
[ -d "$DIR" ] && [ -w "$DIR" ] || { msg "Cannot write to $DIR. Ask an administrator for access, then run this again." "$DIR 에 쓸 수 없습니다. 관리자에게 권한을 요청한 뒤 다시 실행하세요." >&2; exit 1; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/vibebattery-install.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
msg "Downloading VibeBattery..." "VibeBattery를 내려받는 중..."
curl -fsSL "$BASE/VibeBattery.zip" -o "$TMP/VibeBattery.zip" || { msg "Download failed." "내려받지 못했습니다." >&2; exit 1; }
curl -fsSL "$BASE/VibeBattery.zip.sha256" -o "$TMP/VibeBattery.zip.sha256" || { msg "Download failed." "내려받지 못했습니다." >&2; exit 1; }
( cd "$TMP" && shasum -a 256 -c VibeBattery.zip.sha256 >/dev/null 2>&1 ) || { msg "The download does not match its checksum. Nothing was installed." "내려받은 파일의 체크섬이 맞지 않습니다. 설치하지 않았습니다." >&2; exit 1; }
mkdir "$TMP/x"
ditto -x -k "$TMP/VibeBattery.zip" "$TMP/x"
[ -d "$TMP/x/VibeBattery.app" ] || { msg "The download has no VibeBattery.app." "내려받은 파일에 VibeBattery.app이 없습니다." >&2; exit 1; }
# Only the /Applications copy can be the running one, so a test install leaves the app alone.
[ "$DIR" = /Applications ] && osascript -e 'quit app "VibeBattery"' >/dev/null 2>&1 || true
rm -rf "$DIR/.VibeBattery.app.new"
ditto "$TMP/x/VibeBattery.app" "$DIR/.VibeBattery.app.new"
rm -rf "$DIR/VibeBattery.app"
mv "$DIR/.VibeBattery.app.new" "$DIR/VibeBattery.app"
msg "Installed $DIR/VibeBattery.app" "$DIR/VibeBattery.app 에 설치했습니다."
[ -n "${VB_SKIP_OPEN:-}" ] || open "$DIR/VibeBattery.app"
msg "To uninstall: curl -fsSL https://github.com/y-minion/vibebattery/releases/latest/download/uninstall.sh | sh" "제거하려면: curl -fsSL https://github.com/y-minion/vibebattery/releases/latest/download/uninstall.sh | sh"
