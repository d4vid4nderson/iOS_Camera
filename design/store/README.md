# App Store header

`app-store-header-5244x2950.png` is the 5244×2950 header uploaded in App Store Connect:
the app icon, "Share the roll, not just the shot." and four phones (camera, a roll, a
profile, People) taken from the website's own mockups in `server/src/site.js`, so it
always matches the site.

The headline sits below the top 30% (iOS frosts the top edge of the header and
mirrored text there looked like a reflection), and everything stays inside the middle
~82% of the width so iPad's crop doesn't cut the phones.

To redraw it after changing the site's mockups:

```sh
mkdir -p /tmp/header && cd /tmp/header
for x in mock films app-icon.png; do ln -sfn "$OLDPWD/server/public/$x" "$x"; done
node "$OLDPWD/design/store/make_header.mjs" "$OLDPWD/server/src/site.js" header.html
python3 -m http.server 8765 &      # the mockups use root-relative /mock/ paths
node "$OLDPWD/design/store/shot.js" http://localhost:8765/header.html header.png 2   # 5244×2950
```

Needs Node, Playwright with Chromium, and the Inter font installed.
