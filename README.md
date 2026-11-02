# Film Exposures

A film camera for iPhone (formerly RetroCam / Mono36; the Xcode project and bundle ID keep the old name).  SwiftUI + AVFoundation + Core Image, no dependencies.

## What it does
- Live viewfinder rendered through the film look on the GPU (Metal + Core Image), so what you see is what you get.
- Six original film "stocks": each with its own colour sensitivity, contrast curve, grain and vignette.
  | Stock | Character |
  |---|---|
  | PAN 50 | Fine grain, smooth tones |
  | CLASSIC 400 | Everyday street film |
  | PUSH 3200 | Gritty, inky blacks, heavy grain |
  | RED FILTER | Dark skies, glowing skin (red-filter channel mix) |
  | ORTHO 80 | Red-blind orthochromatic look, cool paper |
  | DARKROOM SEPIA | Faded, warm-toned fibre print |
- Same pipeline applied to the full-resolution still, saved as JPEG to Photos.
- 36-exposure roll counter with REWIND, ±2 EV dial in 1/3 stops, tap to focus/meter, front/back flip.
- Grain re-randomises every frame and scales with resolution, so preview and print match.

## Run it
Requires Xcode 16+ and iOS 17+ on a real iPhone (the simulator has no camera).

1. Open `RetroCam.xcodeproj`.
2. Signing is preset to team `RN599658F9` and bundle ID `com.davidanderson.retrocam`. Check Target RetroCam → Signing & Capabilities shows your team; change both if someone else builds it.
3. Plug in your phone, select it, Run.

## Where to tweak
- `RetroCam/FilmStock.swift` — the stock presets. Add one and it shows up in the picker.
- `RetroCam/FilmLook.swift` — the emulation pipeline (channel mix → tone curve → paper tone → grain → vignette).
- `RetroCam/CameraModel.swift` — capture session, exposure, focus, roll counter.
- `RetroCam/ContentView.swift` — the UI.

## TestFlight (automatic)
Every push to `main` builds with Xcode 26, signs with your Apple Distribution certificate, and uploads to TestFlight (`.github/workflows/testflight.yml`). You can also run it by hand from the Actions tab.

Signing uses your own certificate + profile because this account's API key is refused by Apple's provisioning API (403); the API key is used only for the upload.

Repository secrets (Settings → Secrets and variables → Actions):

| Secret | What | How to get it |
|---|---|---|
| `ASC_KEY_ID` | App Store Connect API key ID | Users and Access → Integrations → App Store Connect API → Team Keys |
| `ASC_ISSUER_ID` | Issuer ID | Same page, above the keys table |
| `ASC_KEY_P8` | Contents of `AuthKey_<id>.p8` | Downloaded once when the key is created |
| `DIST_CERT_P12` | base64 of the Apple Distribution certificate + private key | Keychain Access → My Certificates → right-click *Apple Distribution: …* → Export → `.p12`, then `base64 -i Certificates.p12 \| pbcopy` |
| `DIST_CERT_PASSWORD` | Password chosen during that export | |
| `PROVISIONING_PROFILE` | base64 of an **App Store Connect** profile for `com.davidanderson.retrocam` | developer.apple.com → Profiles → + → App Store Connect → download, then `base64 -i <file>.mobileprovision \| pbcopy` |

Build numbers are `run number + 100`, so they always increase and never clash with manual uploads.
