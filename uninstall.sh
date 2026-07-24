#!/bin/bash
# Stops AltTabClone, removes its LaunchAgent, and deletes the installed app.
set -euo pipefail

APP_NAME="AltTabClone"
LABEL="com.alttabclone.app"
INSTALLED_APP="${HOME}/Applications/${APP_NAME}.app"
AGENT_PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"

echo "==> Unloading the agent…"
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true

echo "==> Removing ${AGENT_PLIST}…"
rm -f "${AGENT_PLIST}"

echo "==> Removing ${INSTALLED_APP}…"
rm -rf "${INSTALLED_APP}"

pkill -x "${APP_NAME}" 2>/dev/null || true

echo "==> Uninstalled."
echo "You may also remove its leftover Accessibility entry in"
echo "System Settings → Privacy & Security → Accessibility."
