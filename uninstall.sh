#!/bin/bash
# Remove Clawde's LaunchAgent (stops auto-start on login).
set -e

PLIST="$HOME/Library/LaunchAgents/com.jeongilin.clawde.plist"

echo "==> stopping and unregistering LaunchAgent"
launchctl bootout "gui/$(id -u)/com.jeongilin.clawde" 2>/dev/null || true

echo "==> removing plist"
rm -f "$PLIST"

echo "==> done: Clawde will no longer start at login"
