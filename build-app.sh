#!/bin/bash
# Builds AltTabClone.app — a proper macOS app bundle that can hold
# Accessibility / Screen Recording permissions stably.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="AltTabClone"
BUILD_DIR=".build/${CONFIG}"
APP_BUNDLE="${APP_NAME}.app"

echo "==> Building (${CONFIG})…"
swift build -c "${CONFIG}"

echo "==> Assembling ${APP_BUNDLE}…"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Ad-hoc code signature with a stable identifier. macOS ties TCC permissions
# (Accessibility, Screen Recording) to the signed bundle identity, so a stable
# ad-hoc signature means permissions survive rebuilds instead of resetting.
echo "==> Code signing (ad-hoc)…"
codesign --force --deep --sign - \
    --identifier "com.alttabclone.app" \
    "${APP_BUNDLE}"

echo "==> Done: $(pwd)/${APP_BUNDLE}"
echo ""
echo "Launch it with:  open ${APP_BUNDLE}"
echo "On first run, grant Accessibility access in"
echo "System Settings → Privacy & Security → Accessibility, then relaunch."
