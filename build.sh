#!/bin/bash
# Builds ROSilicon.app from the Swift package. The app installs into
# ~/Library/Application Support/RO LATAM and carries everything it needs, so it
# can be moved anywhere once built.
#
# Set APP_OUT to build somewhere other than this folder.
set -euo pipefail

cd "$(dirname "$0")"
PKG="$(pwd)"

APP_NAME="ROSilicon"
APP="${APP_OUT:-$PKG}/$APP_NAME.app"
EXECUTABLE="ROSilicon"
VERSION="1.0"

command -v swift >/dev/null 2>&1 || {
    echo "error: swift not found — install Xcode or the command line tools" >&2
    exit 1
}

echo "==> building (release)"
swift build -c release --package-path "$PKG"
BIN="$(swift build -c release --package-path "$PKG" --show-bin-path)/$EXECUTABLE"

# DXVK and the Steam stub ride inside the bundle, so the app installs and runs
# without needing tools/ next to it.
DXVK="$PKG/Resources/d9vk/d3d9.dll"
STEAM_STUB="$PKG/Resources/steam_stub/steam_stub.exe"
for f in "$DXVK" "$STEAM_STUB"; do
    [[ -f "$f" ]] || { echo "error: $f not found" >&2; exit 1; }
done

echo "==> assembling $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$DXVK" "$APP/Contents/Resources/d3d9.dll"
cp "$STEAM_STUB" "$APP/Contents/Resources/steam_stub.exe"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# One .lproj per language; macOS picks the reader's and falls back to English.
LANGUAGES=()
for lproj in "$PKG"/Resources/Localizations/*.lproj; do
    [[ -d "$lproj" ]] || { echo "error: no translations in Resources/Localizations" >&2; exit 1; }
    cp -R "$lproj" "$APP/Contents/Resources/"
    LANGUAGES+=("$(basename "$lproj" .lproj)")
done
echo "==> translations: ${LANGUAGES[*]}"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>        <string>com.rosilicon.launcher</string>
    <key>CFBundleExecutable</key>        <string>$EXECUTABLE</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>CFBundleDevelopmentRegion</key>  <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
$(printf '        <string>%s</string>\n' "${LANGUAGES[@]}")
    </array>
    <key>LSApplicationCategoryType</key> <string>public.app-category.games</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

echo "==> drawing the icon"
swift "$PKG/makeicon.swift" "$APP/Contents/Resources/AppIcon.icns" >/dev/null

# Ad-hoc signature: enough for Gatekeeper to run it locally, and it must not
# use the hardened runtime — the launcher passes DYLD_LIBRARY_PATH down to Wine.
echo "==> signing (ad-hoc)"
codesign --force --sign - "$APP"

# The Finder caches icons per bundle path; touching the app nudges it.
touch "$APP"

echo
echo "Built $APP"
