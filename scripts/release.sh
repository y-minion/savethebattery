#!/bin/sh
# Builds, tags and publishes a release: scripts/release.sh <version>
# Never commits or pushes to main; the version bump lands by PR first.
set -eu
vb_lang() { case "${VB_LANG:-$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2s/[^a-z]*\([a-z]*\).*/\1/p')}" in ko*) echo ko;; *) echo en;; esac; }
msg() { if [ "$(vb_lang)" = ko ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }
die() { printf '%s\n' "$1" >&2; exit 1; }
cd "$(dirname "$0")/.."
V=${1:-}
[ -n "$V" ] || die "usage: scripts/release.sh <version>"
[ -z "$(git status --porcelain)" ] || die "The working tree is not clean."
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "Not on main."
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "main differs from origin/main."
[ "$(sed -n 's/^ *MARKETING_VERSION: *//p' project.yml)" = "$V" ] || die "MARKETING_VERSION in project.yml is not $V."
git rev-parse -q --verify "refs/tags/v$V" >/dev/null && die "Tag v$V already exists."
git ls-remote --exit-code --tags origin "refs/tags/v$V" >/dev/null 2>&1 && die "Tag v$V already exists on origin."
[ -f "docs/release-notes/$V.md" ] || die "docs/release-notes/$V.md is missing."
VB_RELEASE=1 scripts/build-app.sh
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/VibeBattery.app/Contents/Info.plist)" = "$V" ] || die "The built app is not version $V."
ARCHS=$(lipo -archs dist/VibeBattery.app/Contents/MacOS/VibeBattery)
case " $ARCHS " in *" arm64 "*" x86_64 "*|*" x86_64 "*" arm64 "*) ;; *) die "Binary is not universal: $ARCHS";; esac
( cd dist && shasum -a 256 VibeBattery.zip >VibeBattery.zip.sha256 )
cp scripts/install.sh scripts/uninstall.sh dist/
printf 'Version: %s\nArchs: %s\nSHA-256: %s\n' "$V" "$ARCHS" "$(cut -d' ' -f1 dist/VibeBattery.zip.sha256)"
printf 'Publish v%s? [y/N] ' "$V"
read -r ANSWER </dev/tty || ANSWER=n
case "$ANSWER" in y|Y) ;; *) die "Not published.";; esac
git tag -a "v$V" -m "VibeBattery $V"
git push origin "v$V"
gh release create "v$V" --title "VibeBattery $V" --notes-file "docs/release-notes/$V.md" \
    dist/VibeBattery.zip dist/VibeBattery.zip.sha256 dist/install.sh dist/uninstall.sh || {
    printf 'The tag v%s is pushed but the release failed. Re-run the gh release create command by hand, or delete the tag: git push origin :refs/tags/v%s && git tag -d v%s\n' "$V" "$V" "$V" >&2
    exit 1
}
