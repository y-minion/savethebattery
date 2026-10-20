#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
VB_SWIFT=${VB_SWIFT:-swift}
VB_OUTPUT_DIR=${VB_OUTPUT_DIR:-"$PWD/dist"}
"$VB_SWIFT" build --configuration release
VB_BIN_DIR=$("$VB_SWIFT" build --configuration release --show-bin-path)
VB_APP="$VB_OUTPUT_DIR/VibeBattery.app"
mkdir -p "$VB_APP/Contents/MacOS" "$VB_APP/Contents/Resources"
cp "$VB_BIN_DIR/VibeBattery" "$VB_APP/Contents/MacOS/VibeBattery"
cp "$VB_BIN_DIR/vbctl" "$VB_APP/Contents/MacOS/vbctl"
cp "$VB_BIN_DIR/VBChargeHelper" "$VB_APP/Contents/MacOS/VBChargeHelper"
cp scripts/install-helper.sh scripts/uninstall-helper.sh "$VB_APP/Contents/Resources/"
cat > "$VB_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.y-minion.vibebattery</string>
<key>CFBundleName</key><string>VibeBattery</string>
<key>CFBundleDisplayName</key><string>VibeBattery</string>
<key>CFBundleExecutable</key><string>VibeBattery</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Finder may add presentation metadata after a previous local launch. Remove
# only signing-incompatible metadata from this generated bundle.
for VB_ATTRIBUTE in com.apple.FinderInfo com.apple.ResourceFork; do
    xattr -dr "$VB_ATTRIBUTE" "$VB_APP" 2>/dev/null || true
done
codesign --force --sign - "$VB_APP/Contents/MacOS/vbctl"
codesign --force --sign - --identifier io.github.y-minion.vibebattery.helper "$VB_APP/Contents/MacOS/VBChargeHelper"
codesign --force --sign - "$VB_APP"
codesign --verify --strict "$VB_APP"
ditto -c -k --norsrc --noextattr --keepParent "$VB_APP" "$VB_OUTPUT_DIR/VibeBattery.zip"
printf '%s\n' "$VB_APP"
