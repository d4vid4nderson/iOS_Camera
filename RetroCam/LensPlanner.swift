import Foundation

/// One physical camera behind the lens picker, described only by what matters for
/// choosing lenses. Built at runtime from whatever the phone reports, so the app
/// never relies on a list of iPhone models.
struct PhysicalCamera: Equatable {
    /// 35 mm-equivalent focal length.
    var focalLength: Double
    /// Largest photo this camera can deliver in the current format, in megapixels.
    var megapixels: Double
    /// Zoom factor on the (virtual) capture device at which this camera is used natively.
    var zoomFactor: Double
}

/// A lens the user can pick: a 35 mm-equivalent focal length served by one physical
/// camera, natively or as a crop.
struct LensOption: Equatable, Hashable, Identifiable {
    var focalLength: Int
    /// 1 = the camera's native field of view; >1 = cropped in.
    var crop: Double
    /// What to set `videoZoomFactor` to on the capture device.
    var zoomFactor: Double
    /// The most detail this lens gives, in megapixels: its camera's, less what the crop costs.
    var megapixels: Double = 0

    var id: Int { focalLength }
    var name: String { "\(focalLength)mm" }
    var isNative: Bool { crop < 1.0001 }
}

enum LensPlanner {
    /// Classic film-camera focal lengths offered when a camera can crop to them cleanly.
    static let classicFocalLengths: [Double] = [21, 28, 35, 50, 85, 135]
    /// A crop must still leave at least this much real detail.
    static let minimumMegapixels: Double = 8
    /// A classic focal length this close to a native one is redundant (e.g. 50 vs 48).
    static let mergeTolerance: Double = 0.10

    /// Lenses worth offering for this set of cameras, widest first.
    static func lenses(for cameras: [PhysicalCamera]) -> [LensOption] {
        let sorted = cameras.sorted { $0.focalLength < $1.focalLength }
        var options = sorted.map {
            LensOption(focalLength: Int($0.focalLength.rounded()), crop: 1, zoomFactor: $0.zoomFactor, megapixels: $0.megapixels)
        }
        for target in classicFocalLengths {
            let redundant = options.contains {
                abs(Double($0.focalLength) - target) / target <= mergeTolerance
            }
            if redundant { continue }
            // Crop from the longest camera that is still wider than the target.
            guard let camera = sorted.last(where: { $0.focalLength <= target }) else { continue }
            let crop = target / camera.focalLength
            guard camera.megapixels / (crop * crop) >= minimumMegapixels else { continue }
            options.append(LensOption(focalLength: Int(target), crop: crop,
                                      zoomFactor: camera.zoomFactor * crop,
                                      megapixels: camera.megapixels / (crop * crop)))
        }
        // Two cameras can round to the same focal length; keep the native one.
        var seen = Set<Int>()
        return options
            .sorted { ($0.focalLength, $0.crop) < ($1.focalLength, $1.crop) }
            .filter { seen.insert($0.focalLength).inserted }
    }

    /// The lens to select: the one closest to `preferred` (the user's last choice),
    /// otherwise the camera closest to a normal 26 mm main camera.
    static func defaultLens(in lenses: [LensOption], preferred: Int?) -> LensOption? {
        let target = Double(preferred ?? 26)
        return lenses.min { abs(Double($0.focalLength) - target) < abs(Double($1.focalLength) - target) }
    }

    /// 35 mm-equivalent focal length from a camera's horizontal field of view.
    /// Uses the diagonal, like Apple's quoted focal lengths, for a 4:3 sensor
    /// (diagonal = 1.25 x width; full-frame diagonal = 43.27 mm).
    static func equivalentFocalLength(horizontalFieldOfView degrees: Double) -> Double {
        let halfAngle = degrees * .pi / 360
        return (43.27 / 2) / (tan(halfAngle) * 1.25)
    }
}
