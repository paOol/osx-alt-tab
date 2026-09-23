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

# Record what the currently-installed copy was signed with, before replacing it.
# codesign prints an implicit requirement as "# designated => …" and an explicit
# one as "designated => …", so strip the marker before comparing — otherwise the
# two forms always look different and this would reset permissions every time.
designated_requirement() {
    codesign -d -r- "$1" 2>&1 | sed -n 's/^#* *designated => //p'
}

OLD_REQ=""
if [ -d "${INSTALLED_APP}" ]; then
    OLD_REQ="$(designated_requirement "${INSTALLED_APP}")"
fi
NEW_REQ="$(designated_requirement "${STAGED_APP}")"

echo "==> Installing to ${INSTALLED_APP}…"
mkdir -p "${INSTALL_DIR}"
rm -rf "${INSTALLED_APP}"
cp -R "${STAGED_APP}" "${INSTALLED_APP}"

# If the designated requirement changed, any existing TCC grant is now stale:
# the app still appears (checked) in System Settings but is not actually
# trusted, and toggling the checkbox won't help because System Settings rewrites
# the row from the stale stored requirement. Clearing the entry is the only way
# to get a working prompt again.
if [ -n "${OLD_REQ}" ] && [ "${OLD_REQ}" != "${NEW_REQ}" ]; then
    echo "==> Signing identity changed — clearing the stale permission entry…"
    tccutil reset Accessibility "${LABEL}" >/dev/null 2>&1 || true
    tccutil reset ScreenCapture "${LABEL}" >/dev/null 2>&1 || true
    echo "    You will need to grant Accessibility access once more."
fi

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
echo "in System Settings → Privacy & Security → Accessibility."
echo "It starts working within a second of the grant — no relaunch needed."
echo ""
echo "To uninstall:  ./uninstall.sh"
