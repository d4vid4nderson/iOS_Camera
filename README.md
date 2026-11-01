# RetroCam

A black & white film camera for iPhone. SwiftUI + AVFoundation + Core Image, no dependencies.

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
Every push to `main` builds with Xcode 26, signs with a cloud-managed distribution certificate, and uploads to TestFlight (`.github/workflows/testflight.yml`). You can also run it by hand from the Actions tab.

One-time setup:
1. App Store Connect → Users and Access → Integrations → App Store Connect API → generate a **Team key** with the **Admin** role. Download the `.p8` (you only get one chance).
2. GitHub repo → Settings → Secrets and variables → Actions → add:
   - `ASC_KEY_ID` — the key's ID
   - `ASC_ISSUER_ID` — the Issuer ID shown above the keys list
   - `ASC_KEY_P8` — the entire contents of the `.p8` file, including the BEGIN/END lines

Build numbers are `run number + 100`, so they always increase and never clash with manual uploads.
