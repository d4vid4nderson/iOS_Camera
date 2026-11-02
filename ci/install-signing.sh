#!/usr/bin/env bash
# Install the Apple Distribution certificate and App Store provisioning profile
# from repository secrets into a throwaway keychain. Prints only metadata
# (identity name, profile name/app ID/team/expiry), never key material.
#
# Env: DIST_CERT_P12 (base64 .p12), DIST_CERT_PASSWORD, PROVISIONING_PROFILE (base64
#      .mobileprovision), TEAM_ID, BUNDLE_ID, RUNNER_TEMP, GITHUB_ENV
set -euo pipefail

fail() { echo "::error::$*"; exit 1; }

KEYCHAIN="$RUNNER_TEMP/signing.keychain-db"
KEYCHAIN_PASS="$(uuidgen)"
P12="$RUNNER_TEMP/dist.p12"
PROFILE="$RUNNER_TEMP/profile.mobileprovision"
PROFILE_PLIST="$RUNNER_TEMP/profile.plist"

# --- Certificate -------------------------------------------------------------
printf '%s' "$DIST_CERT_P12" | tr -d '[:space:]' | base64 --decode > "$P12" \
  || fail "DIST_CERT_P12 isn't valid base64. On the Mac run: base64 -i Certificates.p12 | pbcopy  and paste the result."
security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
if ! security import "$P12" -P "$DIST_CERT_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN" >/dev/null; then
  rm -f "$P12"
  fail "Couldn't import the certificate. Usually DIST_CERT_PASSWORD doesn't match the password chosen when exporting the .p12."
fi
rm -f "$P12"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null
# shellcheck disable=SC2046
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')

IDENTITIES="$(security find-identity -v -p codesigning "$KEYCHAIN")"
echo "Signing identities in keychain:"
echo "$IDENTITIES" | sed 's/^/  /'
echo "$IDENTITIES" | grep -q "Apple Distribution" \
  || fail "No 'Apple Distribution' identity in DIST_CERT_P12. Export the Apple Distribution certificate *with its private key* (expand it in Keychain Access, select both, then Export)."
echo "$IDENTITIES" | grep -q "($TEAM_ID)" \
  || fail "The Apple Distribution certificate isn't for team $TEAM_ID."

# --- Provisioning profile ----------------------------------------------------
printf '%s' "$PROVISIONING_PROFILE" | tr -d '[:space:]' | base64 --decode > "$PROFILE" \
  || fail "PROVISIONING_PROFILE isn't valid base64. On the Mac run: base64 -i <file>.mobileprovision | pbcopy  and paste the result."
security cms -D -i "$PROFILE" > "$PROFILE_PLIST" 2>/dev/null \
  || fail "PROVISIONING_PROFILE isn't a .mobileprovision file."
pb() { /usr/libexec/PlistBuddy -c "Print :$1" "$PROFILE_PLIST" 2>/dev/null || true; }
UUID="$(pb UUID)"
NAME="$(pb Name)"
APP_ID="$(pb Entitlements:application-identifier)"
PROFILE_TEAM="$(pb TeamIdentifier:0)"
EXPIRES="$(pb ExpirationDate)"
echo "Profile: '$NAME' | app ID $APP_ID | team $PROFILE_TEAM | expires $EXPIRES"
[ "$APP_ID" = "$TEAM_ID.$BUNDLE_ID" ] \
  || fail "Profile is for app ID '$APP_ID', expected '$TEAM_ID.$BUNDLE_ID'. Create an App Store profile for $BUNDLE_ID."
if /usr/libexec/PlistBuddy -c "Print :ProvisionedDevices" "$PROFILE_PLIST" >/dev/null 2>&1; then
  fail "Profile '$NAME' is a Development or Ad Hoc profile (it lists devices). Create one of type 'App Store Connect'."
fi

# --- Entitlements the profile allows ------------------------------------------
# Sign in with Apple and links that open the app (Associated Domains) need both the
# capability on the App ID and a profile made after it was switched on. Include each
# entitlement only if this profile carries it, so an older profile still signs (without
# them) instead of failing the build.
ENTITLEMENTS="$RUNNER_TEMP/app.entitlements"
has() { /usr/libexec/PlistBuddy -c "Print :Entitlements:$1" "$PROFILE_PLIST" >/dev/null 2>&1; }
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  echo '<plist version="1.0"><dict>'
  if has com.apple.developer.applesignin; then
    echo '<key>com.apple.developer.applesignin</key><array><string>Default</string></array>'
    echo "Profile allows Sign in with Apple: on."
  else
    echo "::warning::This provisioning profile doesn't include Sign in with Apple, so the build leaves it off. Switch it on for $BUNDLE_ID, re-save the App Store profile and update PROVISIONING_PROFILE."
  fi
  if has com.apple.developer.associated-domains; then
    echo '<key>com.apple.developer.associated-domains</key><array><string>applinks:filmexposures.com</string></array>'
    echo "Profile allows Associated Domains: links to filmexposures.com open the app."
  else
    echo "::warning::This provisioning profile doesn't include Associated Domains, so filmexposures.com links open the web page first. Switch it on for $BUNDLE_ID, re-save the profile and update PROVISIONING_PROFILE."
  fi
  echo '</dict></plist>'
} > "$ENTITLEMENTS"
plutil -lint "$ENTITLEMENTS" >/dev/null || fail "Couldn't write the entitlements file."
echo "APP_ENTITLEMENTS=$ENTITLEMENTS" >> "$GITHUB_ENV"

for dir in "$HOME/Library/MobileDevice/Provisioning Profiles" \
           "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
  mkdir -p "$dir"
  cp "$PROFILE" "$dir/$UUID.mobileprovision"
done
rm -f "$PROFILE" "$PROFILE_PLIST"

{
  echo "KEYCHAIN=$KEYCHAIN"
  echo "PROFILE_UUID=$UUID"
} >> "$GITHUB_ENV"
echo "Signing installed"
