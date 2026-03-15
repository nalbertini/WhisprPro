#!/bin/bash
set -euo pipefail

# WhisprPro DMG Builder
# Usage: ./scripts/build-dmg.sh [output-dir]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
VERSION=$(grep 'MARKETING_VERSION' "$PROJECT_DIR/project.yml" | head -1 | awk '{print $2}' | tr -d '"')

echo "=== WhisprPro DMG Builder ==="
echo "Version: $VERSION"
echo "Output: $OUTPUT_DIR"
echo ""

# Ensure Xcode project is up to date
echo "[1/6] Generating Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate 2>/dev/null

# Check if whisper.cpp xcframework exists
if [ ! -d "Packages/WhisperCpp/libwhisper.xcframework" ]; then
    echo "[!] whisper.cpp xcframework not found. Building..."
    echo "    Run the setup steps from README.md first."
    exit 1
fi

# Archive
echo "[2/6] Archiving..."
ARCHIVE_PATH="/tmp/WhisprPro-release.xcarchive"
rm -rf "$ARCHIVE_PATH"
xcodebuild -scheme WhisprPro \
    -configuration Release \
    -destination 'platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    archive -quiet

echo "[3/6] Exporting .app..."
EXPORT_PATH="/tmp/WhisprPro-export"
rm -rf "$EXPORT_PATH"

cat > /tmp/export-options.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist /tmp/export-options.plist \
    -quiet 2>/dev/null

echo "[4/6] Creating DMG..."
DMG_STAGING="/tmp/WhisprPro-dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$EXPORT_PATH/WhisprPro.app" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

mkdir -p "$OUTPUT_DIR"
DMG_PATH="$OUTPUT_DIR/WhisprPro-$VERSION.dmg"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "WhisprPro $VERSION" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH" \
    -quiet

echo "[5/6] Cleaning up..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$DMG_STAGING" /tmp/export-options.plist

# Stats
DMG_SIZE=$(du -h "$DMG_PATH" | awk '{print $1}')
APP_SIZE=$(du -sh "$EXPORT_PATH/WhisprPro.app" 2>/dev/null || echo "N/A")

echo "[6/6] Done!"
echo ""
echo "=== Build Complete ==="
echo "DMG: $DMG_PATH ($DMG_SIZE)"
echo ""
echo "To distribute:"
echo "  1. Open the DMG and verify the app launches"
echo "  2. For notarization: xcrun notarytool submit $DMG_PATH --apple-id YOUR_ID --team-id YOUR_TEAM --password YOUR_APP_PASSWORD"
echo "  3. After notarization: xcrun stapler staple $DMG_PATH"
