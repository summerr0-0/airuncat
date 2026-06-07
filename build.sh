#!/bin/bash
# Build airuncat and assemble a .app bundle (no Xcode required, CLT only).
set -e
cd "$(dirname "$0")"

echo "==> swift build -c release"
swift build -c release

APP="airuncat.app"
BIN=".build/release/airuncat"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/airuncat"
cp Info.plist "$APP/Contents/Info.plist"

echo "==> codesign with stable self-signed identity (so Accessibility grant persists across rebuilds)"
if security find-certificate -c "airuncat Self-Signed" >/dev/null 2>&1; then
  codesign --force --deep --sign "airuncat Self-Signed" --identifier com.jeongilin.airuncat "$APP"
else
  echo "   WARN: 'airuncat Self-Signed' cert not found -> ad-hoc (Accessibility will reset each build)"
  codesign --force --deep --sign - --identifier com.jeongilin.airuncat "$APP" >/dev/null 2>&1 || true
fi

echo "==> done: $(pwd)/$APP"

# Install LaunchAgent so airuncat starts automatically on login.
PLIST="$HOME/Library/LaunchAgents/com.jeongilin.airuncat.plist"
APP_BIN="$(pwd)/$APP/Contents/MacOS/airuncat"

echo "==> installing LaunchAgent"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.jeongilin.airuncat</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_BIN</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/com.jeongilin.airuncat" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "==> LaunchAgent registered: $PLIST"
