#!/bin/sh
# Builds dist/Save the Battery.app with Xcode (so the Shortcuts actions' metadata ships) and signs it.
# Shortcuts only lists actions from apps signed with a team: set STB_SIGN_IDENTITY, or the first
# "Apple Development" identity in the keychain is used. Without one the build is ad-hoc.
set -eu
stb_lang() { case "${STB_LANG:-$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2s/[^a-z]*\([a-z]*\).*/\1/p')}" in ko*) echo ko;; *) echo en;; esac; }
msg() { if [ "$(stb_lang)" = ko ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }
cd "$(dirname "$0")/.."
STB_OUTPUT_DIR=${STB_OUTPUT_DIR:-"$PWD/dist"}
STB_DERIVED="$PWD/.build/xcode"
STB_SIGN_IDENTITY=${STB_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: .*\)"$/\1/p' | head -1)}
STB_SIGN_IDENTITY=${STB_SIGN_IDENTITY:--}
# STB_RELEASE=1: refuse ad-hoc signing and require a secure timestamp on every signature.
STB_TS=
if [ "${STB_RELEASE:-}" = 1 ]; then
    [ "$STB_SIGN_IDENTITY" != - ] || { msg "A release build needs an Apple Development identity." "릴리스 빌드에는 Apple Development 서명 인증서가 필요합니다." >&2;exit 1; }
    STB_TS=--timestamp
fi
mkdir -p "$STB_DERIVED"
xcodebuild -project SaveTheBattery.xcodeproj -scheme SaveTheBatteryApp -configuration Release -derivedDataPath "$STB_DERIVED" build >"$STB_DERIVED/build.log" 2>&1 || { tail -40 "$STB_DERIVED/build.log";exit 1; }
# Sign outside the output folder: a synced folder (iCloud Documents) can re-add
# Finder metadata mid-build, which strict signature checks reject.
STB_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/savethebattery-build.XXXXXX")
trap 'rm -rf "$STB_STAGE"' EXIT
STB_APP="$STB_STAGE/Save the Battery.app"
ditto --norsrc --noextattr "$STB_DERIVED/Build/Products/Release/Save the Battery.app" "$STB_APP"
codesign --force $STB_TS --sign "$STB_SIGN_IDENTITY" "$STB_APP/Contents/MacOS/stb"
# The helper only trusts its own identifier; Xcode signs tools with a generated one.
codesign --force $STB_TS --sign "$STB_SIGN_IDENTITY" --identifier io.github.y-minion.savethebattery.helper "$STB_APP/Contents/MacOS/STBChargeHelper"
codesign --force $STB_TS --sign "$STB_SIGN_IDENTITY" "$STB_APP"
codesign --verify --strict "$STB_APP"
if [ "${STB_RELEASE:-}" = 1 ]; then
    for t in "$STB_APP" "$STB_APP/Contents/MacOS/stb" "$STB_APP/Contents/MacOS/STBChargeHelper"; do
    codesign -dvv "$t" 2>&1 | grep -q '^Timestamp=' || { msg "The signature has no secure timestamp." "서명에 보안 타임스탬프가 없습니다." >&2;exit 1; }
    done
fi
for f in Contents/Resources/Metadata.appintents Contents/Resources/install-helper.sh Contents/Resources/uninstall-helper.sh Contents/MacOS/stb Contents/MacOS/STBChargeHelper; do
    [ -e "$STB_APP/$f" ] || { msg "The build is missing $f." "빌드 결과에 $f 가 없습니다." >&2;exit 1; }
done
codesign -dv "$STB_APP/Contents/MacOS/STBChargeHelper" 2>&1 | grep -q '^Identifier=io.github.y-minion.savethebattery.helper$' || { msg "The helper signing identifier does not match." "헬퍼 서명 식별자가 다릅니다." >&2;exit 1; }
# A drag-to-Applications disk image for browser downloads; the zip stays for install.sh and the in-app update.
STB_DMG_ROOT="$STB_STAGE/dmg"
mkdir "$STB_DMG_ROOT"
ditto --norsrc --noextattr "$STB_APP" "$STB_DMG_ROOT/Save the Battery.app"
ln -s /Applications "$STB_DMG_ROOT/Applications"
hdiutil create -quiet -volname "Save the Battery" -srcfolder "$STB_DMG_ROOT" -fs HFS+ -format UDZO -ov "$STB_STAGE/savethebattery.dmg"
if [ "$STB_SIGN_IDENTITY" != - ]; then
    codesign --force $STB_TS --sign "$STB_SIGN_IDENTITY" "$STB_STAGE/savethebattery.dmg"
    if [ "${STB_RELEASE:-}" = 1 ]; then
        codesign -dvv "$STB_STAGE/savethebattery.dmg" 2>&1 | grep -q '^Timestamp=' || { msg "The disk image signature has no secure timestamp." "디스크 이미지 서명에 보안 타임스탬프가 없습니다." >&2;exit 1; }
    fi
fi
mkdir -p "$STB_OUTPUT_DIR"
rm -rf "$STB_OUTPUT_DIR/Save the Battery.app"
ditto --norsrc --noextattr "$STB_APP" "$STB_OUTPUT_DIR/Save the Battery.app"
ditto -c -k --norsrc --noextattr --keepParent "$STB_APP" "$STB_OUTPUT_DIR/savethebattery.zip"
cp "$STB_STAGE/savethebattery.dmg" "$STB_OUTPUT_DIR/savethebattery.dmg"
msg "Architectures: $(lipo -archs "$STB_APP/Contents/MacOS/Save the Battery")" "아키텍처: $(lipo -archs "$STB_APP/Contents/MacOS/Save the Battery")"
[ "$STB_SIGN_IDENTITY" = - ] && msg "Built with an ad-hoc signature. Actions will not show up in the Shortcuts app." "임시 서명으로 빌드했습니다. 단축어 앱에는 동작이 보이지 않습니다." >&2
printf '%s\n' "$STB_OUTPUT_DIR/Save the Battery.app"
