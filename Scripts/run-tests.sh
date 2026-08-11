#!/bin/zsh
# Builds and runs the unit tests with only Command Line Tools installed
# (no Xcode). With Xcode present, prefer: swift test   or   xcodebuild test.
#
# All app sources and test sources are compiled into a single module with
# -D TEST_RUNNER, which (a) compiles out the app's @main and the tests'
# @testable imports, and (b) compiles in the Swift Testing entry point in
# AutoclickerTests/TestSupport.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
BUILD=${BUILD_DIR:-.build-clt}
mkdir -p "$BUILD"

EXTRA_FLAGS=()
# Workaround for the CLT duplicate-SwiftBridging-modulemap bug, if present.
if [[ -f Scripts/swiftflags.sh ]]; then
  source Scripts/swiftflags.sh
  EXTRA_FLAGS=("${SWIFT_FLAGS[@]}")
else
  EXTRA_FLAGS=(-swift-version 5 -target arm64-apple-macos13.0)
fi

# The Swift Testing macros (#expect, @Test, @Suite) need their compiler
# plugin. It normally auto-discovers, but under a custom module-cache /
# VFS-overlay build it must be pointed at explicitly.
PLUGINS=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins

swiftc \
  "${EXTRA_FLAGS[@]}" \
  -plugin-path "$PLUGINS" \
  -parse-as-library \
  -D TEST_RUNNER \
  -F "$FRAMEWORKS" -framework Testing \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  $(find Autoclicker AutoclickerTests -name "*.swift") \
  -o "$BUILD/autoclicker-tests"

exec "$BUILD/autoclicker-tests" "$@"
