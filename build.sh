#!/bin/zsh
# Builds and packages OpenShuttler.app
# Usage: ./build.sh [--install] [--zip] [--dmg] [--package]
# Optional env var: SWIFTPM_FLAGS="--disable-sandbox"
set -euo pipefail
cd "$(dirname "$0")"

APP="build/OpenShuttler.app"
FLAGS=(${=SWIFTPM_FLAGS:-})

swift build -c release --arch arm64 "${FLAGS[@]}"
BIN="$(swift build -c release --arch arm64 "${FLAGS[@]}" --show-bin-path)/OpenShuttler"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OpenShuttler"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Ad-hoc code signing for local execution
codesign --force --sign - "$APP"
echo "✅ Built: $APP"

if [[ "${*:-}" =~ "--zip" || "${*:-}" =~ "--package" ]]; then
    ZIP="build/OpenShuttler-macOS-arm64.zip"
    rm -f "$ZIP"
    (cd build && zip -q -r "OpenShuttler-macOS-arm64.zip" "OpenShuttler.app")
    echo "📦 Release archive ready: $ZIP"
fi

if [[ "${*:-}" =~ "--dmg" || "${*:-}" =~ "--package" ]]; then
    DMG="build/OpenShuttler-macOS-arm64.dmg"
    DMG_TMP="build/dmg-staging"
    rm -rf "$DMG" "$DMG_TMP"
    mkdir -p "$DMG_TMP"
    cp -R "$APP" "$DMG_TMP/"
    ln -s /Applications "$DMG_TMP/Applications"

    hdiutil create -volname "OpenShuttler" \
                   -srcfolder "$DMG_TMP" \
                   -ov -format UDZO \
                   "$DMG" >/dev/null
    rm -rf "$DMG_TMP"
    echo "💿 Disk image ready: $DMG"
fi

if [[ "${*:-}" =~ "--package" || ("${*:-}" =~ "--zip" && "${*:-}" =~ "--dmg") ]]; then
    CHECKSUMS="build/SHA256SUMS.txt"
    (cd build && shasum -a 256 OpenShuttler-macOS-arm64.* > "SHA256SUMS.txt")
    echo "🔐 Generated checksums: $CHECKSUMS"
fi

if [[ "${*:-}" =~ "--install" ]]; then
    mkdir -p "$HOME/Applications"
    pkill -x OpenShuttler 2>/dev/null || true
    pkill -x MyOwnShutter 2>/dev/null || true
    rm -rf "$HOME/Applications/OpenShuttler.app"
    cp -R "$APP" "$HOME/Applications/"
    echo "✅ Installed to ~/Applications/OpenShuttler.app"
fi
