#!/bin/zsh
# Builds a distributable Autoclicker.app (universal: Apple Silicon + Intel)
# and wraps it in a DMG that can be shared with other people.
#
#   zsh Scripts/package-release.sh
#
# Output: dist/Autoclicker-<version>.dmg
#
# NOTE ON SIGNING: with no Apple Developer ID this build is ad-hoc signed,
# so macOS Gatekeeper will block it on other Macs until the user explicitly
# allows it (see the included "Read Me First" instructions). Signing and
# notarizing with a paid Apple Developer account is the only way to make it
# open with no warnings.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0}"
BUILD=".build-release"
DIST="dist"
APP="$BUILD/Autoclicker.app"

EXTRA_FLAGS=()
if [[ -f Scripts/swiftflags.sh ]]; then
  source Scripts/swiftflags.sh
  # Keep the toolchain workaround flags but drop the fixed -target so we can
  # build each architecture in turn.
  for f in "${SWIFT_FLAGS[@]}"; do
    [[ "$f" == "-target" || "$f" == arm64-apple-macos* ]] && continue
    [[ "$f" == "-swift-version" || "$f" == "5" ]] && continue
    EXTRA_FLAGS+=("$f")
  done
fi

rm -rf "$BUILD" "$DIST"
mkdir -p "$BUILD" "$DIST" "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=($(find Autoclicker -name "*.swift"))

# Build each slice separately, then fuse into one universal binary so the app
# runs natively on both Apple Silicon and Intel Macs.
for ARCH in arm64 x86_64; do
  echo "Compiling $ARCH…"
  swiftc -O -wmo -swift-version 5 \
    -target "${ARCH}-apple-macos13.0" \
    "${EXTRA_FLAGS[@]}" \
    -parse-as-library \
    "${SOURCES[@]}" \
    -o "$BUILD/Autoclicker-$ARCH"
done

echo "Creating universal binary…"
lipo -create "$BUILD/Autoclicker-arm64" "$BUILD/Autoclicker-x86_64" \
  -output "$APP/Contents/MacOS/Autoclicker"

[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>Autoclicker</string>
	<key>CFBundleIdentifier</key><string>com.sambesley.Autoclicker</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleName</key><string>Autoclicker</string>
	<key>CFBundleDisplayName</key><string>Autoclicker</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$VERSION</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSSupportsAutomaticTermination</key><false/>
	<key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

echo "Signing (ad-hoc)…"
# Deep ad-hoc signature. Without a Developer ID this is the best available;
# it keeps the bundle internally consistent so macOS doesn't call it damaged.
codesign --force --deep --sign - --options runtime "$APP" 2>/dev/null \
  || codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "  signature OK"

# Instructions that ride along in the DMG, since Gatekeeper will block a
# non-notarized app and most people won't know the way around it.
cat > "$BUILD/Read Me First.txt" <<'TXT'
Autoclicker — installation
==========================

1. Drag Autoclicker into the Applications folder.

2. The first time you open it, macOS will refuse, saying Autoclicker
   "is damaged" or that it cannot check it for malicious software.
   This is expected: the app is not signed with a paid Apple Developer
   certificate. It is not damaged.

   To open it:
     - Open System Settings > Privacy & Security
     - Scroll down to the Security section
     - Next to "Autoclicker was blocked", click "Open Anyway"
     - Confirm with your password / Touch ID

   (On older macOS you can instead right-click the app > Open > Open.)

   IF THAT DOESN'T WORK — if macOS insists the app is "damaged" and no
   "Open Anyway" button appears — open the Terminal app and paste this
   line, then press Return:

     xattr -dr com.apple.quarantine /Applications/Autoclicker.app

   That removes the "downloaded from the internet" flag. Then open the app
   normally. It only has to be done once.

3. Grant Accessibility permission when asked:
     System Settings > Privacy & Security > Accessibility
     -> turn Autoclicker ON

   This is required. The app uses it to detect your trigger button and to
   send the clicks. Without it the app cannot click at all.

4. Open Autoclicker, go to the Trigger section, click "Detect Input",
   press the mouse button or key you want to use, then click
   "Assign as Trigger". Turn on "TRIGGER ARMED" on the Dashboard.

Emergency stop: Command + Shift + Escape stops all clicking instantly,
from anywhere, even inside a game. You can change it in the Safety section.

Requires macOS 13 (Ventura) or newer. Runs natively on both Apple Silicon
and Intel Macs.
TXT

echo "Building DMG…"
STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
cp "$BUILD/Read Me First.txt" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="$DIST/Autoclicker-$VERSION.dmg"
hdiutil create -volname "Autoclicker" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo ""
echo "Done: $DMG"
echo "Size: $(du -h "$DMG" | cut -f1)"
echo ""
echo "Share that .dmg file. Recipients must follow 'Read Me First.txt' to"
echo "get past Gatekeeper, because the app is not notarized."
