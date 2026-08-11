#!/bin/zsh
# Builds Autoclicker.app with only Command Line Tools installed (no Xcode).
# With Xcode present, prefer opening Autoclicker.xcodeproj and pressing Run.
#
# Output: .build-clt/Autoclicker.app   (ad-hoc signed)
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=${BUILD_DIR:-.build-clt}
APP="$BUILD/Autoclicker.app"
mkdir -p "$BUILD"

EXTRA_FLAGS=()
# Workaround for the CLT duplicate-SwiftBridging-modulemap bug, if present.
if [[ -f Scripts/swiftflags.sh ]]; then
  source Scripts/swiftflags.sh
  EXTRA_FLAGS=("${SWIFT_FLAGS[@]}")
else
  EXTRA_FLAGS=(-swift-version 5 -target arm64-apple-macos13.0)
fi

echo "Compiling…"
swiftc \
  "${EXTRA_FLAGS[@]}" \
  -parse-as-library \
  -O \
  $(find Autoclicker -name "*.swift") \
  -o "$BUILD/Autoclicker"

echo "Bundling…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/Autoclicker" "$APP/Contents/MacOS/Autoclicker"

# App icon. Regenerate with: python3 Scripts/make-icon.py
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Autoclicker</string>
	<key>CFBundleIdentifier</key>
	<string>com.sambesley.Autoclicker.clt</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleName</key>
	<string>Autoclicker</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS treats the bundle as a stable identity for the
# Accessibility / Input Monitoring permission lists.
codesign --force --sign - "$APP"
echo "Built $APP"
echo "Run with: open $APP"
