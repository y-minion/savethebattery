#!/bin/sh
# Runs install.sh against a fake local release and a temp install dir (never /Applications).
set -eu
cd "$(dirname "$0")/.."
ROOT=$PWD
[ -f dist/savethebattery.zip ] || { echo "Run scripts/build-app.sh first." >&2; exit 1; }
T=$(mktemp -d "${TMPDIR:-/tmp}/stb-install-test.XXXXXX")
trap 'hdiutil detach -quiet "$T/mnt" 2>/dev/null || true; chmod -R u+w "$T" 2>/dev/null || true; rm -rf "$T"' EXIT
export STB_LANG=en STB_SKIP_OPEN=1
fail() { echo "FAIL: $1" >&2; exit 1; }
REL=$T/release; mkdir "$REL"
cp dist/savethebattery.zip "$REL/"
( cd "$REL" && shasum -a 256 savethebattery.zip >savethebattery.zip.sha256 )

# 1. good install, twice into the same dir (second run replaces the first)
D=$T/apps; mkdir "$D"
for run in 1 2; do
    STB_RELEASE_BASE="file://$REL" STB_INSTALL_DIR="$D" sh "$ROOT/scripts/install.sh" >"$T/out1" 2>&1 || { cat "$T/out1"; fail "install $run failed"; }
    [ -d "$D/Save the Battery.app" ] || fail "app missing after run $run"
    codesign --verify --strict "$D/Save the Battery.app" || fail "signature check after run $run"
    [ ! -e "$D/.Save the Battery.app.new" ] && [ ! -e "$D/.Save the Battery.app.old" ] || fail "staging left behind after run $run"
done

# 2. corrupt checksum: nonzero exit, install dir unchanged
D2=$T/apps2; mkdir "$D2"
BAD=$T/bad; mkdir "$BAD"; cp "$REL/savethebattery.zip" "$BAD/"
echo "0000000000000000000000000000000000000000000000000000000000000000  savethebattery.zip" >"$BAD/savethebattery.zip.sha256"
if STB_RELEASE_BASE="file://$BAD" STB_INSTALL_DIR="$D2" sh "$ROOT/scripts/install.sh" >"$T/out2" 2>&1; then fail "bad checksum accepted"; fi
[ -z "$(ls -A "$D2")" ] || fail "install dir changed after bad checksum"

# 3. unwritable dir
D3=$T/ro; mkdir "$D3"; chmod 555 "$D3"
if STB_RELEASE_BASE="file://$REL" STB_INSTALL_DIR="$D3" sh "$ROOT/scripts/install.sh" >"$T/out3" 2>&1; then fail "unwritable dir accepted"; fi
grep -qi "administrator" "$T/out3" || { cat "$T/out3"; fail "admin message missing"; }

# 4. disk image: mounts read-only with the signed app and an Applications link
[ -f dist/savethebattery.dmg ] || fail "dist/savethebattery.dmg missing"
mkdir "$T/mnt"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$T/mnt" dist/savethebattery.dmg || fail "disk image does not mount"
[ -d "$T/mnt/Save the Battery.app" ] || fail "disk image has no app"
[ "$(readlink "$T/mnt/Applications")" = /Applications ] || fail "disk image has no Applications link"
codesign --verify --strict "$T/mnt/Save the Battery.app" || fail "app signature inside the disk image"
hdiutil detach -quiet "$T/mnt"
echo "install tests passed"
