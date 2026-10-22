#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
APP="$ROOT/TD Capture.app"
STAGE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/TDCapture-build.XXXXXX")
STAGE="$STAGE_ROOT/TD Capture.app"
trap 'rm -rf "$STAGE_ROOT"' EXIT
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx15.0 \
  -module-cache-path "${TMPDIR:-/tmp}/CameoStudioModuleCache-v2" \
  "$ROOT/Sources/"*.swift -o "$STAGE/Contents/MacOS/TDCapture" \
  -framework AppKit -framework AVFoundation -framework ScreenCaptureKit -framework CoreImage -framework UniformTypeIdentifiers -framework Vision
cp "$ROOT/Assets/TDCapture.icns" "$STAGE/Contents/Resources/TDCapture.icns"
cp "$ROOT/Assets/Backgrounds/"*.png "$STAGE/Contents/Resources/"
cp -R "$ROOT/Resources/Localizations" "$STAGE/Contents/Resources/Localizations"
cp "$ROOT/Info.plist" "$STAGE/Contents/Info.plist"
codesign --force --sign - --identifier local.joyce.CameoStudio "$STAGE"
codesign --verify --deep --strict "$STAGE"
if /usr/bin/pgrep -x TDCapture >/dev/null 2>&1 || /usr/bin/pgrep -x CameoStudio >/dev/null 2>&1; then
  echo "Please quit TD Capture before installing the new build."
  exit 1
fi
# Replace the bundle after compilation/signing; never rewrite the live executable.
if [[ -d "$APP" ]]; then mv "$APP" "$STAGE_ROOT/Previous.app"; fi
if ! mv "$STAGE" "$APP"; then
  if [[ -d "$STAGE_ROOT/Previous.app" ]]; then mv "$STAGE_ROOT/Previous.app" "$APP"; fi
  exit 1
fi
touch "$APP"
echo "Built: $APP"
