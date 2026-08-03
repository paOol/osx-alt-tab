#!/bin/bash
# Builds AltTabClone.app — a proper macOS app bundle that can hold
# Accessibility / Screen Recording permissions stably.
#
# The bundle is staged inside .build/ rather than the project root, so the only
# app at a launchable, Spotlight-visible path is the one ./install.sh puts in
# ~/Applications. Two copies would mean two entries in the Accessibility list
# and no way to tell which one is running.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="AltTabClone"
BUILD_DIR=".build/${CONFIG}"
APP_BUNDLE=".build/${APP_NAME}.app"

# Older revisions of this script staged the bundle in the project root; drop any
# leftover so it can't shadow the installed copy.
rm -rf "${APP_NAME}.app"

echo "==> Building (${CONFIG})…"
swift build -c "${CONFIG}"

echo "==> Assembling ${APP_BUNDLE}…"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# macOS ties TCC permissions (Accessibility, Screen Recording) to the app's
# *designated requirement* — the rule it stores at grant time and re-evaluates
# on every launch. By default an ad-hoc signature gets
#     cdhash H"<binary hash>"
# which changes on every relink, so each rebuild silently invalidates the grant:
# the app still shows as checked in System Settings but isn't actually trusted.
#
# Supplying the requirement explicitly pins it to the bundle identifier instead,
# which is stable across rebuilds. That means no certificate, no keychain and no
# setup step — grant Accessibility once and it holds for every future build.
#
# The tradeoff: a requirement this loose is satisfied by *any* ad-hoc binary
# claiming this identifier, so the grant isn't bound to this build in particular.
# For a locally-built personal tool that's an acceptable trade; an app shipped to
# other people should use a real Developer ID certificate, which gets both
# stability and binding.
BUNDLE_ID="com.alttabclone.app"
DESIGNATED_REQUIREMENT="designated => identifier \"${BUNDLE_ID}\""

echo "==> Code signing (ad-hoc, identifier-pinned)…"
codesign --force --sign - \
    --identifier "${BUNDLE_ID}" \
    -r="${DESIGNATED_REQUIREMENT}" \
    "${APP_BUNDLE}"

echo "==> Designated requirement:"
codesign -d -r- "${APP_BUNDLE}" 2>&1 | grep '^designated' | sed 's/^/    /'

# Guard against a silent regression here: if this ever emits a cdhash-based
# requirement again, permissions would start resetting on every rebuild and the
# only symptom would be the confusing "already enabled but keeps asking" loop.
if ! codesign --verify -R="identifier \"${BUNDLE_ID}\"" "${APP_BUNDLE}" 2>/dev/null; then
    echo "!!! Designated requirement is not identifier-pinned." >&2
    echo "!!! Accessibility permission will reset on every rebuild." >&2
    exit 1
fi

echo "==> Done: $(pwd)/${APP_BUNDLE}"
echo ""
echo "This is a staging copy. Install it (single copy in ~/Applications,"
echo "runs at login) with:  ./install.sh"
