#!/bin/sh
# Installs the latest Save the Battery release into /Applications without sudo.
# curl -fsSL https://github.com/y-minion/savethebattery/releases/latest/download/install.sh | sh
# Test overrides: STB_RELEASE_BASE, STB_INSTALL_DIR, STB_SKIP_OPEN.
set -eu
stb_lang() { case "${STB_LANG:-$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2s/[^a-z]*\([a-z]*\).*/\1/p')}" in ko*) echo ko;; *) echo en;; esac; }
msg() { if [ "$(stb_lang)" = ko ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }
main() {
BASE=${STB_RELEASE_BASE:-https://github.com/y-minion/savethebattery/releases/latest/download}
DIR=${STB_INSTALL_DIR:-/Applications}
NAME="Save the Battery.app"
OS=$(sw_vers -productVersion)
# uname -m says x86_64 under Rosetta; the hardware flag is 1 on Apple silicon either way.
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ]; then ARCH=arm64; else ARCH=x86_64; fi
[ "${OS%%.*}" -ge 15 ] || { msg "Save the Battery needs macOS 15 or later (this Mac runs $OS)." "Save the Battery는 macOS 15 이상이 필요합니다 (이 Mac은 $OS)." >&2; exit 1; }
if [ "$ARCH" = arm64 ] && [ "$(printf '%s\n26.4\n' "$OS" | sort -V | head -1)" = 26.4 ]; then
    msg "macOS $OS on $ARCH: everything is supported, including the charge limit." "macOS $OS ($ARCH): 충전 상한을 포함한 모든 기능을 지원합니다."
else
    msg "macOS $OS on $ARCH: supported, but the charge limit needs Apple silicon and macOS 26.4 or later." "macOS $OS ($ARCH): 사용할 수 있지만 충전 상한은 Apple 실리콘과 macOS 26.4 이상이 필요합니다."
fi
[ -d "$DIR" ] && [ -w "$DIR" ] || { msg "Cannot write to $DIR. Ask an administrator for access, then run this again." "$DIR 에 쓸 수 없습니다. 관리자에게 권한을 요청한 뒤 다시 실행하세요." >&2; exit 1; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/savethebattery-install.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
msg "Downloading Save the Battery..." "Save the Battery를 내려받는 중..."
curl -fsSL "$BASE/savethebattery.zip" -o "$TMP/savethebattery.zip" || { msg "Download failed." "내려받지 못했습니다." >&2; exit 1; }
curl -fsSL "$BASE/savethebattery.zip.sha256" -o "$TMP/savethebattery.zip.sha256" || { msg "Download failed." "내려받지 못했습니다." >&2; exit 1; }
( cd "$TMP" && shasum -a 256 -c savethebattery.zip.sha256 >/dev/null 2>&1 ) || { msg "The download does not match its checksum. Nothing was installed." "내려받은 파일의 체크섬이 맞지 않습니다. 설치하지 않았습니다." >&2; exit 1; }
mkdir "$TMP/x"
ditto -x -k "$TMP/savethebattery.zip" "$TMP/x"
[ -d "$TMP/x/$NAME" ] || { msg "The download has no $NAME." "내려받은 파일에 $NAME 이 없습니다." >&2; exit 1; }
# Only the /Applications copy can be the running one, so a test install leaves the app alone.
if [ "$DIR" = /Applications ] && pgrep -x "Save the Battery" >/dev/null 2>&1; then
    osascript -e 'quit app "Save the Battery"' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "Save the Battery" >/dev/null 2>&1 || break; sleep 1; done
fi
APP="$DIR/$NAME"
rm -rf "$DIR/.$NAME.new" "$DIR/.$NAME.old"
ditto "$TMP/x/$NAME" "$DIR/.$NAME.new"
[ -e "$APP" ] && mv "$APP" "$DIR/.$NAME.old"
if ! mv "$DIR/.$NAME.new" "$APP"; then
    [ -e "$DIR/.$NAME.old" ] && mv "$DIR/.$NAME.old" "$APP"
    rm -rf "$DIR/.$NAME.new"
    msg "Could not put the new app in place. The previous version was restored." "새 앱을 설치하지 못했습니다. 이전 버전을 복원했습니다." >&2; exit 1
fi
rm -rf "$DIR/.$NAME.old"
msg "Installed $APP" "$APP 에 설치했습니다."
[ -n "${STB_SKIP_OPEN:-}" ] || open "$APP"
msg "To uninstall: curl -fsSL https://github.com/y-minion/savethebattery/releases/latest/download/uninstall.sh | sh" "제거하려면: curl -fsSL https://github.com/y-minion/savethebattery/releases/latest/download/uninstall.sh | sh"
}
main "$@"
