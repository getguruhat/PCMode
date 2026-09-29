#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
cd "$ROOT"
swift build -c release

APP="$ROOT/PCMode.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PCMode "$APP/Contents/MacOS/PCMode"
cp AppInfo.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp HatMenu.png "$APP/Contents/Resources/HatMenu.png"
cp SettingsIcons/*.png "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP" >/dev/null
"$ROOT/../create-dmg-installer.sh" "$APP" "PC Mode" "$ROOT/PCMode-Installer.dmg"
echo "$APP"
