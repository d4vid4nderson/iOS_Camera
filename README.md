# Film Exposures

A film camera for iPhone: load a roll of 36 on a film you choose, shoot it, and share the whole roll. The website is [filmexposures.com](https://filmexposures.com).

Formerly RetroCam / Mono36; the Xcode project, scheme and bundle ID keep the old name. The app is SwiftUI + AVFoundation + Core Image with no third-party dependencies. The website and share links run on a small Cloudflare Worker in `server/`.

## What it does

### Rolls
- A roll is 36 frames on one film. Several rolls can be on the go at once, and a roll can be finished early.
- Frames develop when you choose: instantly, when the roll ends, or the morning after it ends.
- Each roll gets its own album in Photos, inside a "Film Exposures" folder. The app keeps its own copy of every frame too, so the roll viewer still shows the whole roll if a photo is deleted from Photos.
- A roll can be printed as a contact sheet: strips of six frames on dark film base, with sprocket holes and edge print.

### Films
Twenty-six built-in films, seven black & white and nineteen color.

| Black & white | Character |
|---|---|
| CLASSIC 400 | The everyday street film |
| PAN 50 | Fine grain, smooth tones |
| SILVER 100 | Bright and crisp, fine sharp grain |
| PUSH 3200 | Pushed hard: gritty, crushed blacks |
| NOIR 400 | Low key: deep shadows, bright highlights |
| MATTE 400 | Faded blacks, soft highlights |
| EXPIRED 200 | Foggy, flat and grainy. Out of date in '98 |

| Color | Character |
|---|---|
| WARM 400 | Warm skin, soft highlights |
| GOLDEN 100 | Low sun, rich and warm |
| EARTH 200 | Tan and olive, clean whites |
| MEADOW 400 | Bright, hazy, sun-bleached |
| TIDE 200 | Teal water, orange light |
| DUSK 800 | Teal-green evenings, gold skies |
| NORTH 400 | Blue shadows, a warm glow |
| STANDARD 200 | Colors as they were, gentle contrast |
| VIVID 100 | Bold color, strong contrast |
| CONTEMPORARY 160 | Open shadows, a rosy tint |
| CHROME 100 | Muted color, quiet contrast |
| CLASSIC 250 | Warm and faded, firm contrast |
| BLEACH 400 | Drained color, cold blue air |
| ETERNAL 400 | Bold color, a magenta cast |
| PURE 100 | Light and even, soft highlights |
| CINE 500 | Warm and gentle, like a film print |
| SILVER 400 | Cool and steely, open shadows |
| TEAL 200 | Cool blue-green, calm and cinematic |
| BRASS 200 | A golden glow in the light |

Any film can be adjusted and saved as your own:
- **Black & white:** a color filter (yellow, orange, red, green, blue, ortho, infrared), the tone curve, and print toning (sepia, cool, selenium, split, gold, platinum, cyanotype, tintype).
- **Color:** white balance, saturation, per-channel curves and split toning.
- **Both:** grain, vignette, bloom, halation, fog and exposure.

A film's whole recipe can be shared as a link or QR code, and whoever opens it can add the film to their own app.

### Camera
- The live viewfinder is drawn through the film look on the GPU (Metal + Core Image), and the same recipe is applied to the full-resolution photo.
- Six formats, each a centered crop of the sensor with its own resolution cap:

  | Format | Shape | Cap |
  |---|---|---|
  | 4×5 | 5:4 | 50 MP |
  | 6×4.5 | 4:3 | 36 MP |
  | 6×6 | 1:1 | 36 MP |
  | 35MM | 3:2 | 24 MP |
  | 16:9 | 16:9 | 24 MP |
  | XPAN | 65:24 | 24 MP |

- Lenses: the phone's own cameras, plus the classic focal lengths (21, 28, 35, 50, 85, 135mm) wherever a crop still leaves at least 8 MP.
- Eleven lens and print effects: fisheye, swirl, tilt-shift, zoom, drag, double, prism, ripple, halftone, etch and kaleido.
- Four borders: none, white, black and slide mount.
- An aperture dial, f/1.4 to f/16, that blurs what is nearer or farther than the focus point using the phone's depth map. The blur is drawn as a lens makes it, with out-of-focus lights taking the aperture's shape: round, or a polygon of 5 to 9 blades. It works on the back lenses that can measure depth (the main lens and longer, on phones with two or more back cameras), and photos are about 12 MP while it is open.
- A date back that burns the date, or date and time, into the corner in seven-segment digits.
- ±2 EV exposure dial in 1/3 stops, tap to focus and meter, flash, front/back flip.
- Seven shutter finishes (copper, silver, black, red, cobalt, olive, brass). The finish is also the app's accent color, and the app icon can be changed to match.
- A Control Center / Lock Screen control and a Shortcuts action that open the app on the viewfinder (iOS 18+).

Photos are saved as JPEG.

### Sharing and people
- The camera needs no account. Signing in (Apple, Google or Facebook) is only for sharing.
- Each roll has an audience: private, specific people, followers, public, or anyone with the link. Rolls start private and stay on the phone until shared.
- Link-shared rolls are deleted from the server 30 days after sharing. Rolls on a profile stay until they're made private again.
- Profiles have an @handle (`filmexposures.com/@handle`), followers that the owner approves, and likes on frames.
- People can be reported and blocked, and an account can be deleted from the profile screen.
- Rolls, films and profiles each have a share card that goes out with the link.

## Run it
The app target runs on iOS 17+; the camera control extension needs iOS 18+. Use a real iPhone, since the simulator has no camera. CI builds with Xcode 26, which App Store Connect requires for uploads.

1. Open `RetroCam.xcodeproj`.
2. Signing is preset to team `RN599658F9` and bundle ID `com.davidanderson.retrocam` (the extension is `com.davidanderson.retrocam.controls`). Check that Target RetroCam → Signing & Capabilities shows your team; change these if someone else builds it.
3. Plug in your phone, select it, Run.

## Where things are

| Path | What |
|---|---|
| `RetroCam/FilmStock.swift` | The film presets. Add one to `FilmStock.all` and it shows up in the picker. |
| `RetroCam/FilmLook.swift`, `ColorGrade.swift` | The emulation pipeline, black & white and color |
| `RetroCam/LensFX.swift`, `LensPlanner.swift` | Lens effects, and which focal lengths a phone offers |
| `RetroCam/DepthOfField.swift`, `Bokeh.ci.metal` | The aperture dial and its depth-of-field blur |
| `RetroCam/FrameFormat.swift`, `PrintBorder.swift`, `DateStamp.swift` | Formats, borders and the date back |
| `RetroCam/CameraModel.swift` | Capture session, exposure, focus, flash |
| `RetroCam/Roll.swift`, `RollStore.swift`, `RollAlbums.swift`, `Darkroom.swift` | Rolls, the app's copies, Photos albums, developing |
| `RetroCam/ContentView.swift` | The camera UI |
| `RetroCam/RollViewer.swift`, `ContactSheet.swift` | Your rolls and their contact sheets |
| `RetroCam/Account.swift`, `Social.swift`, `RollShare.swift`, `ShareAPI.swift` | Accounts, audiences, followers, uploading rolls |
| `RetroCam/FilmCode.swift`, `ShareLinks.swift` | Film recipe links and the share host |
| `Controls/`, `Shared/` | The Control Center / Lock Screen control and its intent |
| `server/` | The Cloudflare Worker: website, share links, accounts, profiles. See `server/README.md`. |
| `ci/` | Signing and upload scripts, plus the lens and film model tests |
| `design/` | Brand marks, the icon generator and the App Store header |
| `docs/export-compliance.md` | Encryption answers for App Store Connect |

## CI
Three workflows in `.github/workflows/`:

| Workflow | When | What |
|---|---|---|
| `build.yml` | Pull requests and pushes to `main` | Server tests, lens and film model tests, unsigned iOS build |
| `testflight.yml` | Every push to `main`, or by hand | Archive, sign, upload to TestFlight |
| `server.yml` | Pushes to `main` that touch `server/`, or by hand | Test and deploy the Worker to filmexposures.com |

## TestFlight (automatic)
Every push to `main` builds with Xcode 26, signs with your Apple Distribution certificate, and uploads to TestFlight. This includes pushes that only change docs. You can also run it by hand from the Actions tab.

Signing uses your own certificate and profile because this account's API key is refused by Apple's provisioning API (403); the API key is used only for the upload.

Repository secrets (Settings → Secrets and variables → Actions):

| Secret | What | How to get it |
|---|---|---|
| `ASC_KEY_ID` | App Store Connect API key ID | Users and Access → Integrations → App Store Connect API → Team Keys |
| `ASC_ISSUER_ID` | Issuer ID | Same page, above the keys table |
| `ASC_KEY_P8` | Contents of `AuthKey_<id>.p8` | Downloaded once when the key is created |
| `DIST_CERT_P12` | base64 of the Apple Distribution certificate + private key | Keychain Access → My Certificates → right-click *Apple Distribution: …* → Export → `.p12`, then `base64 -i Certificates.p12 \| pbcopy` |
| `DIST_CERT_PASSWORD` | Password chosen during that export | |
| `PROVISIONING_PROFILE` | base64 of an **App Store Connect** profile for `com.davidanderson.retrocam` | developer.apple.com → Profiles → + → App Store Connect → download, then `base64 -i <file>.mobileprovision \| pbcopy` |
| `PROVISIONING_PROFILE_CONTROLS` | Optional: the same for `com.davidanderson.retrocam.controls` | As above, for the extension's App ID. Without it the build leaves the camera control out. |

Build numbers are `run number + 100`, so they always increase and never clash with manual uploads.

The server's own secrets (Cloudflare, Facebook, the support inbox) are listed at the top of `.github/workflows/server.yml`; `server/README.md` covers the setup.
