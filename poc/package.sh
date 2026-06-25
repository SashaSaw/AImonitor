#!/bin/sh
# Build AImonitor.app — a double-clickable accessory app (no Dock icon).
# Needs Xcode command-line tools (`xcode-select --install`).
set -e
cd "$(dirname "$0")"

APP="AImonitor.app"
echo "Compiling..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O overlay.swift -o "$APP/Contents/MacOS/AImonitor"
cp Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc sign so macOS runs it without complaint (locally built = no quarantine).
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"

echo "Built $APP"
echo "Launch it with:  open $APP        (or double-click in Finder)"
echo "Move it to /Applications to keep it handy:  mv $APP /Applications/"
