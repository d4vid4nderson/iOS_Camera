// Checks LensPlanner against camera setups from published iPhone specs, so lens
// choices for phones nobody on the team owns are still verified on every build.
// Run: swiftc RetroCam/LensPlanner.swift ci/lens-tests/main.swift -o lens-tests && ./lens-tests
import Foundation

var failures = 0

func expect(_ name: String, _ cameras: [PhysicalCamera], lenses expected: [Int]) {
    let got = LensPlanner.lenses(for: cameras).map(\.focalLength)
    if got == expected {
        print("PASS  \(name): \(got.map { "\($0)mm" }.joined(separator: " "))")
    } else {
        print("FAIL  \(name): expected \(expected), got \(got)")
        failures += 1
    }
}

func cam(_ focal: Double, _ mp: Double, zoom: Double) -> PhysicalCamera {
    PhysicalCamera(focalLength: focal, megapixels: mp, zoomFactor: zoom)
}

// Single camera
expect("SE-style: one 12 MP 28mm camera", [cam(28, 12, zoom: 1)], lenses: [28])
expect("Air-style: one 48 MP 26mm camera", [cam(26, 48, zoom: 1)], lenses: [26, 35, 50])

// Two cameras (non-Pro)
expect("Two cameras, 12 MP ultra-wide", [cam(13, 12, zoom: 1), cam(26, 48, zoom: 2)], lenses: [13, 26, 35, 50])
expect("Two cameras, 48 MP ultra-wide", [cam(13, 48, zoom: 1), cam(26, 48, zoom: 2)], lenses: [13, 21, 26, 35, 50])

// Three cameras (Pro)
expect("Older Pro, all 12 MP, 2x tele", [cam(13, 12, zoom: 1), cam(26, 12, zoom: 2), cam(52, 12, zoom: 4)], lenses: [13, 26, 52])
expect("Recent Pro, all 48 MP, 4x tele", [cam(13, 48, zoom: 1), cam(24, 48, zoom: 1.85), cam(100, 48, zoom: 7.7)],
       lenses: [13, 21, 24, 28, 35, 50, 100, 135])

// Front camera
expect("Front camera (28mm crop keeps 8.1 MP)", [cam(23, 12, zoom: 1)], lenses: [23, 28])

// Crop lenses zoom from the right camera; native lenses use the camera's own zoom exactly
let pro = LensPlanner.lenses(for: [cam(13, 48, zoom: 1), cam(24, 48, zoom: 1.85), cam(100, 48, zoom: 7.7)])
func zoom(_ mm: Int) -> Double { pro.first { $0.focalLength == mm }!.zoomFactor }
for (mm, want) in [(13, 1.0), (24, 1.85), (100, 7.7), (35, 1.85 * 35 / 24), (135, 7.7 * 1.35)] {
    if abs(zoom(mm) - want) < 1e-9 { print("PASS  zoom for \(mm)mm = \(String(format: "%.3f", want))") }
    else { print("FAIL  zoom for \(mm)mm: expected \(want), got \(zoom(mm))"); failures += 1 }
}

// Default selection
let air = LensPlanner.lenses(for: [cam(26, 48, zoom: 1)])
for (preferred, want) in [(nil, 26), (35, 35), (100, 50)] as [(Int?, Int)] {
    let got = LensPlanner.defaultLens(in: air, preferred: preferred)?.focalLength
    if got == want { print("PASS  default lens (preferred \(preferred.map(String.init) ?? "none")) = \(want)mm") }
    else { print("FAIL  default lens (preferred \(String(describing: preferred))): expected \(want), got \(String(describing: got))"); failures += 1 }
}

// Field of view -> focal length (a typical main camera is ~69 degrees wide at 4:3)
let mainFocal = LensPlanner.equivalentFocalLength(horizontalFieldOfView: 69.4)
if (24...26).contains(mainFocal) { print("PASS  69.4 deg -> \(String(format: "%.1f", mainFocal))mm") }
else { print("FAIL  69.4 deg -> \(mainFocal)mm, expected 24-26"); failures += 1 }

print(failures == 0 ? "\nAll lens planner checks passed" : "\n\(failures) lens planner check(s) FAILED")
exit(failures == 0 ? 0 : 1)
