#!/bin/bash
# Notarizes build/Ogle.app, as signed by SIGN_IDENTITY=... ./build.sh, staples the ticket to
# it, and writes build/Ogle.zip for distribution.
#
# Needs notary credentials in the keychain, saved once with:
#   xcrun notarytool store-credentials ogle-notary
# NOTARY_PROFILE names another saved profile.
set -euo pipefail
cd "$(dirname "$0")/.."

app=build/Ogle.app
zip=build/Ogle.zip
profile=${NOTARY_PROFILE:-ogle-notary}

codesign --verify --strict --deep "$app"
if codesign -dv "$app" 2>&1 | grep -q 'Signature=adhoc'; then
  echo "$app is signed ad hoc; build it with SIGN_IDENTITY set first" >&2
  exit 1
fi

rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
# Zip again so the download carries the stapled ticket.
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
spctl --assess --type execute --verbose "$app"
echo "Notarized $app, packaged as $zip"
