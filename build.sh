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

# Install LaunchAgent so Clawde starts automatically on login.
PLIST="$HOME/Library/LaunchAgents/com.jeongilin.clawde.plist"
APP_BIN="$(pwd)/$APP/Contents/MacOS/Clawde"

echo "==> installing LaunchAgent"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.jeongilin.clawde</string>
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

launchctl bootout "gui/$(id -u)/com.jeongilin.clawde" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "==> LaunchAgent registered: $PLIST"
