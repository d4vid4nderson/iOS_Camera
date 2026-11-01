"""Check the App Store Connect API credentials before xcodebuild uses them.

Asks Apple's API directly so a bad Issuer ID, a mismatched Key ID/.p8, a
missing agreement, a missing app record, or a Team ID mismatch each fail
with a specific message. Prints formats, counts and Apple's error text,
never the secret values.
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
problems = []


def err(msg):
    problems.append(msg)
    print(f"::error::{msg}")


raw_key_id = os.environ["ASC_KEY_ID"]
raw_issuer = os.environ["ASC_ISSUER_ID"]
key_id = "".join(raw_key_id.split())
issuer = "".join(raw_issuer.split())
for name, raw, clean in (("ASC_KEY_ID", raw_key_id, key_id), ("ASC_ISSUER_ID", raw_issuer, issuer)):
    if raw != clean:
        print(f"::warning::{name} contained spaces or line breaks ({len(raw) - len(clean)} removed). Trimmed automatically.")
team_id = os.environ["TEAM_ID"]
bundle_id = os.environ["BUNDLE_ID"]
private_key = open(os.environ["KEY_PATH"]).read()

# 1. Formats
if re.fullmatch(r"[A-Z0-9]{10}", key_id):
    print("ASC_KEY_ID: looks right (10 letters/digits)")
else:
    err(f"ASC_KEY_ID doesn't look like a Key ID ({len(key_id)} chars; expected 10 capital letters/digits, "
        "the part of AuthKey_XXXXXXXXXX.p8 between 'AuthKey_' and '.p8').")
if re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", issuer.lower()):
    print("ASC_ISSUER_ID: looks right (UUID with dashes)")
else:
    err(f"ASC_ISSUER_ID doesn't look like an Issuer ID ({len(issuer)} chars, {issuer.count('-')} dashes; "
        "expected xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx from the top of App Store Connect -> "
        "Users and Access -> Integrations -> App Store Connect API -> Team Keys).")
if re.fullmatch(r"[A-Z0-9]{10}", issuer):
    err("ASC_ISSUER_ID looks like a Key ID or Team ID, not an Issuer ID.")

now = int(time.time())
token = jwt.encode(
    {"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
    private_key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"},
)


def get(path, params):
    url = f"{API}{path}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except ValueError:
            return e.code, {}


def apple_errors(body):
    return "; ".join(f"{e.get('code')}: {e.get('detail') or e.get('title')}" for e in body.get("errors", [])) or "no detail"


# 2. Do the key, Issuer ID and .p8 belong together? Is the app record there?
status, body = get("/v1/apps", {"filter[bundleId]": bundle_id, "fields[apps]": "name,bundleId"})
if status == 401:
    err("Apple rejected the API key (401). The Key ID, Issuer ID and .p8 don't belong together: "
        "check ASC_ISSUER_ID is the Issuer ID shown above the Team Keys table, and ASC_KEY_ID matches "
        f"the .p8 file's name. Apple says: {apple_errors(body)}")
elif status == 403:
    err(f"Apple refused access (403). Usually a pending agreement (App Store Connect -> Business, or "
        f"developer.apple.com/account) or a key without enough access. Apple says: {apple_errors(body)}")
elif status != 200:
    err(f"Unexpected response from App Store Connect ({status}): {apple_errors(body)}")
else:
    print("API key: accepted by Apple")
    apps = [a for a in body.get("data", []) if a["attributes"].get("bundleId") == bundle_id]
    if apps:
        print(f"App record: found ('{apps[0]['attributes'].get('name')}', {bundle_id})")
    else:
        err(f"No App Store Connect app uses bundle ID {bundle_id}. Create it under Apps -> + -> New App.")

    # 3. Which team owns the bundle ID?
    status, body = get("/v1/bundleIds", {"filter[identifier]": bundle_id,
                                         "fields[bundleIds]": "identifier,seedId,platform"})
    if status == 200:
        ids = [b for b in body.get("data", []) if b["attributes"].get("identifier") == bundle_id]
        if not ids:
            err(f"Bundle ID {bundle_id} isn't registered to this account (Certificates, Identifiers & Profiles -> Identifiers).")
        else:
            seed = ids[0]["attributes"].get("seedId")
            if seed == team_id:
                print(f"Team: bundle ID is registered to team {team_id}, matching the project")
            else:
                err(f"Team ID mismatch: {bundle_id} is registered to team {seed}, but the project and "
                    f"ExportOptions use {team_id}. Update DEVELOPMENT_TEAM and ci/ExportOptions.plist to {seed}.")
    else:
        err(f"Couldn't read bundle IDs ({status}): {apple_errors(body)}")

if problems:
    sys.exit(1)
print("Preflight passed")
