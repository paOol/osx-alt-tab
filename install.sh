#!/bin/bash
# Installs AltTabClone to a stable location and registers it to launch at login.
#
# Why a stable location: macOS ties Accessibility / Screen Recording permission
# to the app's signed identity *and* path. Installing into ~/Applications (a
# permanent home) means you grant permission once and it sticks, instead of
# re-granting after every rebuild in the project folder.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="AltTabClone"
LABEL="com.alttabclone.app"
INSTALL_DIR="${HOME}/Applications"
INSTALLED_APP="${INSTALL_DIR}/${APP_NAME}.app"
AGENT_DIR="${HOME}/Library/LaunchAgents"
AGENT_PLIST="${AGENT_DIR}/${LABEL}.plist"
EXEC_PATH="${INSTALLED_APP}/Contents/MacOS/${APP_NAME}"
STAGED_APP=".build/${APP_NAME}.app"

echo "==> Building app bundle…"
./build-app.sh release

echo "==> Installing to ${INSTALLED_APP}…"
mkdir -p "${INSTALL_DIR}"
rm -rf "${INSTALLED_APP}"
cp -R "${STAGED_APP}" "${INSTALLED_APP}"

# Some Macs also have a stray copy in /Applications from a manual drag; leaving
# it there means a second Accessibility entry and a second app at login.
if [ -d "/Applications/${APP_NAME}.app" ]; then
    echo "==> Note: a second copy exists at /Applications/${APP_NAME}.app"
    echo "    Remove it so only ${INSTALLED_APP} remains."
fi

echo "==> Writing LaunchAgent ${AGENT_PLIST}…"
mkdir -p "${AGENT_DIR}"
cat > "${AGENT_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${EXEC_PATH}</string>
    </array>
    <!-- Start at login and keep it running (relaunch if it ever exits). -->
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
PLIST

echo "==> (Re)loading the agent…"
# Unload an old instance if present, then load the new one into the GUI session.
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
# launchd can still be tearing the old service down, which makes an immediate
# bootstrap fail with "Input/output error"; give it a few tries.
for _ in 1 2 3 4 5; do
    launchctl bootstrap "gui/$(id -u)" "${AGENT_PLIST}" 2>/dev/null && break
    sleep 1
done
launchctl kickstart -k "gui/$(id -u)/${LABEL}" 2>/dev/null || true

echo ""
echo "==> Installed. ${APP_NAME} is now running and will start at every login."
echo ""
echo "First-time setup: grant Accessibility access to:"
echo "    ${INSTALLED_APP}"
echo "in System Settings → Privacy & Security → Accessibility,"
echo "then run:  launchctl kickstart -k gui/$(id -u)/${LABEL}"
echo ""
echo "To uninstall:  ./uninstall.sh"
