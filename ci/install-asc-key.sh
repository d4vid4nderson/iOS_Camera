#!/usr/bin/env bash
# Rebuild a clean PEM from whatever was pasted into the ASC_KEY_P8 secret:
# tolerates lost/extra line breaks, CRLF, spaces, smart dashes, and a pasted
# base64 body with no BEGIN/END lines. Never prints the key itself.
set -euo pipefail
out="$1"
raw="${ASC_KEY_P8:-}"
had_begin=no; [[ "$raw" == *"BEGIN PRIVATE KEY"* ]] && had_begin=yes
had_end=no;   [[ "$raw" == *"END PRIVATE KEY"* ]] && had_end=yes
body=$(printf '%s' "$raw" \
  | sed -e 's/BEGIN PRIVATE KEY//g' -e 's/END PRIVATE KEY//g' \
  | LC_ALL=C tr -cd 'A-Za-z0-9+/=')
{
  echo "-----BEGIN PRIVATE KEY-----"
  printf '%s' "$body" | fold -w 64
  echo
  echo "-----END PRIVATE KEY-----"
} > "$out"
chmod 600 "$out"
echo "Key secret: ${#raw} chars pasted, BEGIN line: $had_begin, END line: $had_end, base64 body: ${#body} chars"
if ! openssl pkey -in "$out" -noout 2>/dev/null; then
  echo "::error::ASC_KEY_P8 is not a valid private key even after cleanup. Re-copy the full text of AuthKey_<KeyID>.p8 into the secret."
  exit 1
fi
echo "Key parses OK"
