#!/bin/bash
set -euo pipefail

# =============================================================================
# Tekla Distribution Script
# Archives, signs, notarizes, and packages the app into a DMG.
# =============================================================================

SCHEME="Tekla"
PROJECT="Tekla.xcodeproj"
APP_NAME="Tekla"

ARCHIVE_PATH="build/${APP_NAME}.xcarchive"
EXPORT_PATH="build/export"
DMG_PATH="build/${APP_NAME}.dmg"
EXPORT_OPTIONS="build/ExportOptions.plist"

# --- Read credentials from environment or prompt ---

TEAM_ID="${TEAM_ID:-}"
APPLE_ID="${APPLE_ID:-}"
APP_SPECIFIC_PASSWORD="${APP_SPECIFIC_PASSWORD:-}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-}"

if [ -z "$TEAM_ID" ]; then
    read -rp "Apple Developer Team ID: " TEAM_ID
fi

USE_KEYCHAIN_PROFILE=false
if [ -n "$KEYCHAIN_PROFILE" ]; then
    USE_KEYCHAIN_PROFILE=true
else
    if [ -z "$APPLE_ID" ]; then
        read -rp "Apple ID (email): " APPLE_ID
    fi
    if [ -z "$APP_SPECIFIC_PASSWORD" ]; then
        read -rsp "App-Specific Password: " APP_SPECIFIC_PASSWORD
        echo ""
    fi
fi

# --- Clean ---

echo "==> Cleaning build directory..."
rm -rf build
mkdir -p build

# --- Step 1: Archive ---

echo "==> Archiving ${SCHEME}..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    CODE_SIGN_STYLE="Manual" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    ENABLE_HARDENED_RUNTIME=YES \
    | tail -5

echo "==> Archive complete: $ARCHIVE_PATH"

# --- Step 2: Generate ExportOptions.plist ---

cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
PLIST

# --- Step 3: Export ---

echo "==> Exporting archive..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    | tail -5

APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Export failed — ${APP_PATH} not found."
    exit 1
fi

echo "==> Exported: $APP_PATH"

# --- Step 4: Notarize ---

echo "==> Creating ZIP for notarization..."
ZIP_PATH="build/${APP_NAME}-notarize.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Submitting for notarization (this may take a few minutes)..."
if [ "$USE_KEYCHAIN_PROFILE" = true ]; then
    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait
else
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APP_SPECIFIC_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait
fi

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

# --- Step 5: Create styled DMG ---

echo "==> Creating DMG..."
DMG_TEMP="build/${APP_NAME}-temp.dmg"
DMG_VOLUME="${APP_NAME}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BG_IMG="${SCRIPT_DIR}/dmg_resources/background.png"

# Create a temporary read-write DMG
hdiutil create -size 100m -fs HFS+ -volname "$DMG_VOLUME" "$DMG_TEMP" -quiet

# Mount it
MOUNT_DIR=$(hdiutil attach "$DMG_TEMP" -nobrowse | grep "/Volumes/" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')

# Copy app and create Applications symlink
cp -R "$APP_PATH" "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"

# Copy background image into a hidden folder
mkdir -p "$MOUNT_DIR/.background"
cp "$BG_IMG" "$MOUNT_DIR/.background/background.png"

# Style the DMG with AppleScript
echo "==> Styling DMG window..."
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$DMG_VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 760, 500}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "${APP_NAME}.app" of container window to {165, 200}
        set position of item "Applications" of container window to {495, 200}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Ensure Finder releases the volume
sync

# Unmount
hdiutil detach "$MOUNT_DIR" -quiet

# Convert to compressed read-only DMG
hdiutil convert "$DMG_TEMP" -format UDZO -o "$DMG_PATH" -quiet
rm -f "$DMG_TEMP"

# --- Done ---

echo ""
echo "============================================="
echo "  Distribution complete!"
echo "  DMG: $DMG_PATH"
echo "  The app is signed and notarized."
echo "============================================="
