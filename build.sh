#!/bin/bash
# Builds ROSilicon.app from the Swift package, and a .dmg holding it beside a
# shortcut to /Applications to drag it onto. The app installs into
# ~/Library/Application Support/ROSilicon and carries everything it needs, so it
# can be moved anywhere once built.
#
# Set APP_OUT to build somewhere other than this folder, and pass --no-dmg to
# build only the .app.
set -euo pipefail

cd "$(dirname "$0")"
PKG="$(pwd)"

APP_NAME="ROSilicon"
APP="${APP_OUT:-$PKG}/$APP_NAME.app"
EXECUTABLE="ROSilicon"

# The one place the version is written down; the bundle and the .dmg name both
# come from here.
[[ -f "$PKG/VERSION" ]] || { echo "error: no VERSION file in $PKG" >&2; exit 1; }
VERSION="$(tr -d '[:space:]' < "$PKG/VERSION")"
[[ -n "$VERSION" ]] || { echo "error: $PKG/VERSION is empty" >&2; exit 1; }

MAKE_DMG=1
for arg in "$@"; do
    case "$arg" in
        --no-dmg) MAKE_DMG=0 ;;
        *) echo "usage: $(basename "$0") [--no-dmg]" >&2; exit 2 ;;
    esac
done

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

if [[ "$MAKE_DMG" == 1 ]]; then
    DMG="${APP_OUT:-$PKG}/$APP_NAME-$VERSION.dmg"
    echo "==> packing $(basename "$DMG")"

    STAGE="$(mktemp -d)"
    SCRATCH="$(mktemp -d)"
    RW_DMG="$SCRATCH/rw.dmg"
    MOUNT=""
    cleanup() {
        if [[ -n "$MOUNT" ]]; then
            hdiutil detach "$MOUNT" -force -quiet 2>/dev/null || true
        fi
        rm -rf "$STAGE" "$SCRATCH"
    }
    trap cleanup EXIT

    # What the window holds: the app, and the drop target next to it. ditto
    # rather than cp, so the signature and extended attributes survive.
    ditto "$APP" "$STAGE/$APP_NAME.app"
    ln -s /Applications "$STAGE/Applications"

    # Room for the Finder to write its .DS_Store into the image.
    SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 32 ))
    hdiutil create -quiet -srcfolder "$STAGE" -volname "$APP_NAME" -fs HFS+ \
        -format UDRW -size "${SIZE_MB}m" -ov "$RW_DMG"

    # Mounted wherever hdiutil puts it: a stale ROSilicon volume from an
    # earlier run would otherwise be detached out from under someone.
    ATTACHED="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)"
    MOUNT="$(printf '%s\n' "$ATTACHED" | sed -n 's|.*\(/Volumes/.*\)$|\1|p' | tail -1)"
    [[ -n "$MOUNT" ]] || { echo "error: could not mount $RW_DMG" >&2; exit 1; }
    VOLUME="$(basename "$MOUNT")"

    # Icon positions live in the volume's .DS_Store, which only the Finder
    # writes. It needs permission to be driven by this terminal, so a refusal
    # leaves the layout at the Finder's default rather than failing the build.
    osascript <<APPLESCRIPT >/dev/null || echo "    (skipped the window layout — the Finder said no)"
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 150, 800, 570}
        set viewOptions to icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set position of item "$APP_NAME.app" of container window to {150, 180}
        set position of item "Applications" of container window to {450, 180}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT

    # The icon the volume wears on the desktop and in the sidebar. It goes on
    # after the Finder is done: refreshing the window with the custom-icon flag
    # already set makes the Finder delete the .icns and clear the flag again.
    cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
    if command -v SetFile >/dev/null 2>&1; then SetFile -a C "$MOUNT"; fi

    sync
    hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force -quiet
    MOUNT=""

    rm -f "$DMG"
    hdiutil convert "$RW_DMG" -quiet -format UDZO -imagekey zlib-level=9 -o "$DMG"
    echo "Built $DMG"
fi
