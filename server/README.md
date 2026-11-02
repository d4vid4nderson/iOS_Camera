# Film Exposures share server

A small Cloudflare Worker behind Film Exposures' share links.

| Link | What it does |
|---|---|
| `https://<host>/f/<code>` | A shared film. The whole recipe is in the link, so nothing is stored. It opens Film Exposures and offers to add the film; without the app, it shows a page about the film. |
| `https://<host>/r/<id>` | A shared roll. Its photos are stored in R2 for 30 days, or until the sharer taps UNSHARE. It opens in Film Exposures' viewer. Without the app, the web page shows the roll's card and asks people to get Film Exposures to see the whole roll. |

Rolls with 3 reports are hidden until reviewed. Reports are stored under `reports/<id>/` in the bucket.

## One-time setup

1. **Create a free Cloudflare account** at https://dash.cloudflare.com/sign-up.
2. **Pick a workers.dev subdomain:** go to *Workers & Pages*, open *Subdomain* on the right, and choose a name (e.g. `davidanderson`). The server will then live at `https://exposures.<subdomain>.workers.dev`.
3. **Turn on R2 storage:** go to *R2 Object Storage* and select *Purchase R2 Plan*. The free tier covers 10 GB and 1 million uploads a month, but Cloudflare asks for a payment method before it switches R2 on.
4. **Create an API token:** go to *My Profile*, then *API Tokens*, then *Create Token*, and use the template *Edit Cloudflare Workers*. Add the permission *Account → Workers R2 Storage → Edit*, then create the token.
5. **Add two GitHub repository secrets** (*Settings → Secrets and variables → Actions*). Don't paste the token anywhere else.
   - `CLOUDFLARE_API_TOKEN`: the token from step 4
   - `CLOUDFLARE_ACCOUNT_ID`: shown in the Cloudflare dashboard's right sidebar (*Account ID*)
6. **Deploy:** go to *Actions*, then *Share server*, then *Run workflow*. When it finishes, open `https://exposures.<subdomain>.workers.dev/`; you should see the Film Exposures page.
7. **Set the address in the app:** `ShareLinks.host` in `RetroCam/ShareLinks.swift`.
8. **App Store button:** set `APP_STORE_ID` in `wrangler.toml` to the app's Apple ID (App Store Connect → App Information → Apple ID, a 10-digit number). Or set `APP_STORE_URL` to a public TestFlight link while testing. Until one is set, the pages say Film Exposures is coming soon.

## Your own address: filmexposures.com

Do this before sharing any links for real: links made on the workers.dev address keep pointing there.

1. Buy the domain through Cloudflare (*Domain Registration → Register Domains*). It then lives in the same account, and Cloudflare charges the registry's price with no markup. If you buy it elsewhere, add it to Cloudflare (*Add a domain*) and switch its nameservers to the two Cloudflare gives you.
2. In `wrangler.toml`, uncomment the `routes` line, then run the *Share server* workflow again.
3. Set `ShareLinks.host` to `filmexposures.com`.

## Links that open the app directly (Universal Links)

Until this is done, a tapped link opens the web page first, and its *Open in Film Exposures* button opens the app.

1. In the Apple Developer site, go to *Certificates, IDs & Profiles*, then *Identifiers*, then `com.davidanderson.retrocam`, and tick **Associated Domains**. Save.
2. Under *Profiles*, edit the App Store profile, save it so it picks up the new capability, and download it.
3. Replace the `PROVISIONING_PROFILE` repository secret with the base64 of the new profile: `base64 -i profile.mobileprovision | pbcopy`.
4. Then add the app's `applinks:<host>` entitlement. Adding it before the profile has the capability makes TestFlight builds fail.

## Accounts: public profiles and likes (Sign in with Apple)

Signed in with Apple, people can put rolls on a public profile (`/u/<id>`, which never
expires until they make a roll private) and like frames in other people's rolls. The server
checks Apple's identity token itself (against appleid.apple.com/auth/keys), so there's no
extra secret to add. To switch it on in the app:

1. In the Apple Developer site, open Identifiers -> `com.davidanderson.retrocam` and tick
   **Sign in with Apple**. Save.
2. Profiles -> your App Store profile for the app -> Edit -> Save (it now includes Sign in
   with Apple) -> Download. Put the new profile, base64-encoded, in the
   `PROVISIONING_PROFILE` repository secret, as before.
3. Ask for the `com.apple.developer.applesignin` entitlement to be added to the app. Do this
   *after* step 2: a signed build fails if the entitlement isn't in the profile.

Until then the Sign in with Apple button shows an error and everything else works.

Deleting an account (Profile -> DELETE ACCOUNT) deletes its profile, headshot, likes and
every roll shared while signed in. Before App Review, the server should also revoke the
person's Apple token on deletion, which needs a Sign in with Apple key; that isn't set up yet.

## Tests

```
cd server && npm test
```
