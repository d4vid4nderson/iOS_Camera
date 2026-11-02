# Exposures share server

A small Cloudflare Worker behind Exposures' share links.

| Link | What it does |
|---|---|
| `https://<host>/f/<code>` | A shared film. The whole recipe is in the link, so nothing is stored. It opens Exposures and offers to add the film; without the app, it shows a page about the film. |
| `https://<host>/r/<id>` | A shared roll. Its photos are stored in R2 for 30 days, or until the sharer taps UNSHARE. It opens in Exposures' viewer. Without the app, the web page shows the roll's card and asks people to get Exposures to see the whole roll. |

Rolls with 3 reports are hidden until reviewed. Reports are stored under `reports/<id>/` in the bucket.

## One-time setup

1. **Create a free Cloudflare account** at https://dash.cloudflare.com/sign-up.
2. **Pick a workers.dev subdomain:** go to *Workers & Pages*, open *Subdomain* on the right, and choose a name (e.g. `davidanderson`). The server will then live at `https://exposures.<subdomain>.workers.dev`.
3. **Turn on R2 storage:** go to *R2 Object Storage* and select *Purchase R2 Plan*. The free tier covers 10 GB and 1 million uploads a month, but Cloudflare asks for a payment method before it switches R2 on.
4. **Create an API token:** go to *My Profile*, then *API Tokens*, then *Create Token*, and use the template *Edit Cloudflare Workers*. Add the permission *Account → Workers R2 Storage → Edit*, then create the token.
5. **Add two GitHub repository secrets** (*Settings → Secrets and variables → Actions*). Don't paste the token anywhere else.
   - `CLOUDFLARE_API_TOKEN`: the token from step 4
   - `CLOUDFLARE_ACCOUNT_ID`: shown in the Cloudflare dashboard's right sidebar (*Account ID*)
6. **Deploy:** go to *Actions*, then *Share server*, then *Run workflow*. When it finishes, open `https://exposures.<subdomain>.workers.dev/`; you should see the Exposures page.
7. **Set the address in the app:** `ShareLinks.host` in `RetroCam/ShareLinks.swift`.
8. **App Store button:** set `APP_STORE_ID` in `wrangler.toml` to the app's Apple ID (App Store Connect → App Information → Apple ID, a 10-digit number). Or set `APP_STORE_URL` to a public TestFlight link while testing. Until one is set, the pages say Exposures is coming soon.

## Links that open the app directly (Universal Links)

Until this is done, a tapped link opens the web page first, and its *Open in Exposures* button opens the app.

1. In the Apple Developer site, go to *Certificates, IDs & Profiles*, then *Identifiers*, then `com.davidanderson.retrocam`, and tick **Associated Domains**. Save.
2. Under *Profiles*, edit the App Store profile, save it so it picks up the new capability, and download it.
3. Replace the `PROVISIONING_PROFILE` repository secret with the base64 of the new profile: `base64 -i profile.mobileprovision | pbcopy`.
4. Then add the app's `applinks:<host>` entitlement. Adding it before the profile has the capability makes TestFlight builds fail.

## Tests

```
cd server && npm test
```
