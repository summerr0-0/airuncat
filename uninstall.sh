#!/bin/bash
# Remove airuncat's LaunchAgent (stops auto-start on login).
set -e

PLIST="$HOME/Library/LaunchAgents/com.jeongilin.airuncat.plist"

echo "==> stopping and unregistering LaunchAgent"
launchctl bootout "gui/$(id -u)/com.jeongilin.airuncat" 2>/dev/null || true

echo "==> removing plist"
rm -f "$PLIST"

echo "==> done: airuncat will no longer start at login"
