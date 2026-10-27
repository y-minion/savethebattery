#!/bin/sh
# Runs install.sh against a fake local release and a temp install dir (never /Applications).
set -eu
cd "$(dirname "$0")/.."
ROOT=$PWD
[ -f dist/VibeBattery.zip ] || { echo "Run scripts/build-app.sh first." >&2; exit 1; }
T=$(mktemp -d "${TMPDIR:-/tmp}/vb-install-test.XXXXXX")
trap 'chmod -R u+w "$T" 2>/dev/null || true; rm -rf "$T"' EXIT
export VB_LANG=en VB_SKIP_OPEN=1
fail() { echo "FAIL: $1" >&2; exit 1; }
REL=$T/release; mkdir "$REL"
cp dist/VibeBattery.zip "$REL/"
( cd "$REL" && shasum -a 256 VibeBattery.zip >VibeBattery.zip.sha256 )

# 1. good install
D=$T/apps; mkdir "$D"
VB_RELEASE_BASE="file://$REL" VB_INSTALL_DIR="$D" sh "$ROOT/scripts/install.sh" >"$T/out1" 2>&1 || { cat "$T/out1"; fail "install failed"; }
[ -d "$D/VibeBattery.app" ] || fail "app missing"
codesign --verify --strict "$D/VibeBattery.app" || fail "signature check"
[ ! -e "$D/.VibeBattery.app.new" ] || fail "staging left behind"

# 2. corrupt checksum: nonzero exit, install dir unchanged
D2=$T/apps2; mkdir "$D2"
BAD=$T/bad; mkdir "$BAD"; cp "$REL/VibeBattery.zip" "$BAD/"
echo "0000000000000000000000000000000000000000000000000000000000000000  VibeBattery.zip" >"$BAD/VibeBattery.zip.sha256"
if VB_RELEASE_BASE="file://$BAD" VB_INSTALL_DIR="$D2" sh "$ROOT/scripts/install.sh" >"$T/out2" 2>&1; then fail "bad checksum accepted"; fi
[ -z "$(ls -A "$D2")" ] || fail "install dir changed after bad checksum"

# 3. unwritable dir
D3=$T/ro; mkdir "$D3"; chmod 555 "$D3"
if VB_RELEASE_BASE="file://$REL" VB_INSTALL_DIR="$D3" sh "$ROOT/scripts/install.sh" >"$T/out3" 2>&1; then fail "unwritable dir accepted"; fi
grep -qi "administrator" "$T/out3" || { cat "$T/out3"; fail "admin message missing"; }
echo "install tests passed"
