#!/bin/zsh
# Builds and packages OpenShuttler.app
# Usage: ./build.sh [--install] [--zip]
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

if [[ "${*:-}" =~ "--zip" ]]; then
    ZIP="build/OpenShuttler-macOS-arm64.zip"
    rm -f "$ZIP"
    (cd build && zip -q -r "OpenShuttler-macOS-arm64.zip" "OpenShuttler.app")
    echo "📦 Release archive ready: $ZIP"
fi

if [[ "${*:-}" =~ "--install" ]]; then
    mkdir -p "$HOME/Applications"
    pkill -x OpenShuttler 2>/dev/null || true
    pkill -x MyOwnShutter 2>/dev/null || true
    rm -rf "$HOME/Applications/OpenShuttler.app"
    cp -R "$APP" "$HOME/Applications/"
    echo "✅ Installed to ~/Applications/OpenShuttler.app"
fi
