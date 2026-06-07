#!/bin/bash
# Build Clawde and assemble a .app bundle (no Xcode required, CLT only).
set -e
cd "$(dirname "$0")"

echo "==> swift build -c release"
swift build -c release

APP="Clawde.app"
BIN=".build/release/Clawde"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Clawde"
cp Info.plist "$APP/Contents/Info.plist"

echo "==> codesign with stable self-signed identity (so Accessibility grant persists across rebuilds)"
if security find-certificate -c "Clawde Self-Signed" >/dev/null 2>&1; then
  codesign --force --deep --sign "Clawde Self-Signed" --identifier com.jeongilin.clawde "$APP"
else
  echo "   WARN: 'Clawde Self-Signed' cert not found -> ad-hoc (Accessibility will reset each build)"
  codesign --force --deep --sign - --identifier com.jeongilin.clawde "$APP" >/dev/null 2>&1 || true
fi

echo "==> done: $(pwd)/$APP"
