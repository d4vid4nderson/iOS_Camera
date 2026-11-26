import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// The APERTURE dial (LENS panel). A phone's lens has a fixed opening, so this dial doesn't
/// change the exposure; it changes the depth of field, by blurring what's nearer or farther
/// than the focus point using the phone's depth map. f/16 is the lens stopped right down:
/// everything sharp, no depth map needed, full-resolution photos.
struct Aperture: Equatable {
    /// Whole stops, wide open to stopped down.
    static let stops: [Double] = [1.4, 2, 2.8, 4, 5.6, 8, 11, 16]
    /// Stopped right down: no blur.
    static let closed = 16.0

    var fNumber: Double

    /// Open wider than f/16, so there's blur to draw.
    var isOpen: Bool { fNumber < Self.closed }
    /// "f/1.4", "f/8".
    var label: String { fNumber == fNumber.rounded() ? "f/\(Int(fNumber))" : "f/\(fNumber)" }

    /// Aperture shapes on offer: round, or a polygon with this many blades.
    static let bladeCounts = [0, 5, 6, 7, 8, 9]

    /// The stop closest to `value` (a saved setting, say).
    static func nearest(_ value: Double) -> Aperture {
        Aperture(fNumber: stops.min { abs($0 - value) < abs($1 - value) } ?? closed)
    }
}

/// Depth of field from a disparity map (1/distance, so far is near zero and close is large).
///
/// The blur follows the lens formula: a point's blur circle grows with how far its
/// disparity is from the focus point's, with the square of the focal length, and shrinks
/// with the f-number. So a 26mm lens keeps most of a scene sharp even at f/1.4, and an
/// 85mm melts the background, as real lenses do. Every size is a fraction of the image's
/// long side, so the live preview and the photo match.
enum DepthOfField {
    /// The largest blur radius, as a fraction of the long side.
    static let maxRadius: CGFloat = 0.028
    /// A little more blur than a full-frame lens would give, so wide lenses still show it.
    static let gain: CGFloat = 1.5
    /// How far (in disparity, 1/m) from the focus point still counts as sharp.
    static let tolerance: CGFloat = 0.04
    /// Width of a full-frame negative in mm times 1000 mm/m: turns f² · disparity / N into
    /// a fraction of the frame's width.
    private static let frame: CGFloat = 36_000

    /// A photo's depth, ready for the darkroom.
    struct Shot {
        /// Disparity, upright like the photo, covering the same view.
        var disparity: CIImage
        /// Disparity at the focus point.
        var focus: CGFloat
        var fNumber: Double
        /// 35 mm-equivalent focal length of the lens it was shot with.
        var focalLength: Double
        /// Aperture blades (the shape of out-of-focus lights); under 3 is round.
        var blades: Int = 0
    }

    /// `depthData` as 32-bit disparity.
    static func disparity(from depthData: AVDepthData) -> AVDepthData {
        depthData.depthDataType == kCVPixelFormatType_DisparityFloat32
            ? depthData
            : depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
    }

    /// A disparity map as an image of raw numbers (no colour management).
    static func image(from disparity: AVDepthData) -> CIImage? {
        CIImage(depthData: disparity, options: [CIImageOption.colorSpace.rawValue: NSNull()])
    }

    /// The disparity around `point` (0...1 across and down the map): the median of a small
    /// window, so an edge or a stray reading doesn't decide what's in focus.
    static func focusDisparity(in map: CVPixelBuffer, at point: CGPoint) -> CGFloat? {
        guard CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_DisparityFloat32 else { return nil }
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        let cx = min(max(Int(point.x * CGFloat(width)), 0), width - 1)
        let cy = min(max(Int(point.y * CGFloat(height)), 0), height - 1)
        let reach = max(2, width / 24)
        var values: [Float32] = []
        for y in stride(from: max(cy - reach, 0), through: min(cy + reach, height - 1), by: 2) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in stride(from: max(cx - reach, 0), through: min(cx + reach, width - 1), by: 2) {
                let value = row[x]
                if value.isFinite, value >= 0 { values.append(value) }
            }
        }
        guard !values.isEmpty else { return nil }
        values.sort()
        return CGFloat(values[values.count / 2])
    }

    /// `disparity` stretched to cover `rect` exactly.
    static func fit(_ disparity: CIImage, to rect: CGRect) -> CIImage {
        let source = disparity.extent
        guard source.width > 0, source.height > 0, !source.isInfinite else { return disparity }
        return disparity
            .transformed(by: CGAffineTransform(translationX: -source.minX, y: -source.minY))
            .transformed(by: CGAffineTransform(scaleX: rect.width / source.width, y: rect.height / source.height))
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }

    /// How carefully the blur is drawn.
    enum Quality {
        /// The live viewfinder: 30 times a second, so fewer points and nothing at full size.
        case preview
        /// The photo.
        case photo

        /// The largest copy of the image the blur is gathered on: 0 = full size, 1 = half.
        var firstLevel: Int { self == .photo ? 0 : 1 }
        /// Points gathered per pixel.
        var points: Int { self == .photo ? 72 : 32 }
    }

    /// The largest radius gathered on any one copy of the image, in that copy's pixels.
    /// Bigger blur circles are drawn on a copy half the size, and so on: every blur is a
    /// dense, even shape instead of a sparse pattern of dots.
    private static let gatherRadius: CGFloat = 8
    /// How much more a clipped highlight weighs than a mid-tone (see dofWeigh).
    private static let highlightBoost: CGFloat = 6
    /// How the aperture's polygon is turned, in radians.
    private static let bladeRotation: CGFloat = 0.26

    /// The lens-blur kernels (Bokeh.ci.metal). nil if they can't be loaded, in which case
    /// the plain soft blur is used.
    private static let kernels: (weigh: CIColorKernel, gather: CIKernel)? = {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url),
              let weigh = try? CIColorKernel(functionName: "dofWeigh", fromMetalLibraryData: data),
              let gather = try? CIKernel(functionName: "dofGather", fromMetalLibraryData: data)
        else { return nil }
        return (weigh, gather)
    }()

    /// `image` with everything away from the focus distance blurred, as the lens would at
    /// `fNumber`. `disparity` covers the same view as `image`, at any size. `blades` is the
    /// number of aperture blades (the shape of out-of-focus lights); under 3 is round.
    static func apply(to image: CIImage, disparity: CIImage, focus: CGFloat,
                      fNumber: Double, focalLength: Double, blades: Int = 0,
                      quality: Quality = .photo) -> CIImage {
        let extent = image.extent
        guard fNumber < Aperture.closed, fNumber > 0, focalLength > 0,
              extent.width > 1, extent.height > 1, !extent.isInfinite,
              disparity.extent.width > 0, disparity.extent.height > 0 else { return image }
        // Work with the picture at the origin; put it back at the end.
        let home = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        let local = CGRect(origin: .zero, size: extent.size)
        let source = image.transformed(by: home)
        let long = max(local.width, local.height)
        let circles = blurCircles(disparity: disparity, in: local, focus: focus,
                                  fNumber: fNumber, focalLength: focalLength)
        let blurred = lensBlur(source, circles: circles, in: local, radius: maxRadius * long,
                               blades: blades, quality: quality)
            ?? softBlur(source, circles: circles, in: local, radius: maxRadius * long)
        return blurred.cropped(to: local).transformed(by: home.inverted())
    }

    /// Each pixel's blur circle as a share of the largest one, 0...1 (in every channel).
    private static func blurCircles(disparity: CIImage, in rect: CGRect, focus: CGFloat,
                                    fNumber: Double, focalLength: Double) -> CIImage {
        let long = max(rect.width, rect.height)
        // Blur radius (fraction of the long side) per unit of disparity away from focus,
        // then as a share of the largest radius.
        let perUnit = 0.5 * gain * CGFloat(focalLength * focalLength) / (CGFloat(fNumber) * frame)
        let slope = perUnit / maxRadius
        let fitted = fit(disparity, to: rect)
        // slope · (|d - focus| - tolerance), built as the larger of the two signed sides.
        let near = ramp(fitted, slope: slope, offset: -slope * focus - slope * tolerance, clamped: false)
        let far = ramp(fitted, slope: -slope, offset: slope * focus - slope * tolerance, clamped: false)
        return near
            .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: far])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
            ])
            // The map is far coarser than the picture: soften its steps.
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(long * 0.003))
            .cropped(to: rect)
    }

    /// slope · red + offset in every channel, opaque; optionally held to 0...1.
    private static func ramp(_ image: CIImage, slope: CGFloat, offset: CGFloat, clamped: Bool = true) -> CIImage {
        let row = CIVector(x: slope, y: 0, z: 0, w: 0)
        let out = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": row, "inputGVector": row, "inputBVector": row,
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: offset, y: offset, z: offset, w: 1),
        ])
        guard clamped else { return out }
        return out.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
        ])
    }

    /// `image` at half the size (each pixel the average of four), covering `rect`.
    private static func halved(_ image: CIImage, to rect: CGRect) -> CIImage {
        image.clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
            .cropped(to: rect)
    }

    /// The blur a lens makes: every out-of-focus point spread into the aperture's shape.
    ///
    /// Drawn on a stack of copies of the image, each half the size of the last. Every copy
    /// gathers at most `gatherRadius` of its own pixels, so the full-size copy draws the
    /// slightly soft parts crisply and the small copies draw the big blur circles; each
    /// pixel then takes the largest copy that can hold its blur circle.
    private static func lensBlur(_ image: CIImage, circles: CIImage, in rect: CGRect, radius: CGFloat,
                                 blades: Int, quality: Quality) -> CIImage? {
        guard let kernels,
              var weighted = kernels.weigh.apply(extent: rect, arguments: [image, highlightBoost])
        else { return nil }
        let first = quality.firstLevel
        // The smallest copy has to hold the largest blur circle.
        let last = min(max(Int((log2(max(radius / gatherRadius, 1))).rounded(.up)), first), 6)
        var levelCircles = circles
        var levelRect = rect
        var layers: [(level: Int, image: CIImage)] = []
        for level in 0...last {
            if level > 0 {
                levelRect = CGRect(x: 0, y: 0, width: (levelRect.width / 2).rounded(.up),
                                   height: (levelRect.height / 2).rounded(.up))
                weighted = halved(weighted, to: levelRect)
                levelCircles = halved(levelCircles, to: levelRect)
            }
            guard level >= first else { continue }
            let size = CGFloat(1 << level)
            let reach = gatherRadius + 2
            guard let gathered = kernels.gather.apply(
                extent: levelRect,
                roiCallback: { _, r in r.insetBy(dx: -reach, dy: -reach) },
                arguments: [weighted.clampedToExtent(), levelCircles.clampedToExtent(),
                            radius / size, gatherRadius, CGFloat(blades), bladeRotation,
                            CGFloat(quality.points)])
            else { return nil }
            let full = level == 0 ? gathered : gathered.clampedToExtent()
                .transformed(by: CGAffineTransform(scaleX: size, y: size))
                .cropped(to: rect)
            layers.append((level, full))
        }
        guard var result = layers.last?.image else { return nil }
        // From the smallest copy up: a larger copy takes over wherever the blur circle
        // fits in it, fading in over the last quarter of its reach.
        for layer in layers.dropLast().reversed() {
            let size = CGFloat(1 << layer.level)
            let fits = ramp(circles, slope: -radius / (2 * size), offset: gatherRadius / 2)
            result = layer.image.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: result, kCIInputMaskImageKey: fits,
            ])
        }
        if first > 0 {
            // No full-size copy was drawn: what's in focus (a blur circle under a pixel or
            // so) is the picture itself.
            let sharp = ramp(circles, slope: -radius / 2, offset: 1.5)
            result = image.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: result, kCIInputMaskImageKey: sharp,
            ])
        }
        return result
    }

    /// The fallback: a plain soft blur that grows with the blur circle.
    private static func softBlur(_ image: CIImage, circles: CIImage, in rect: CGRect, radius: CGFloat) -> CIImage {
        let blur = CIFilter.maskedVariableBlur()
        blur.inputImage = image.clampedToExtent()
        blur.mask = circles
        blur.radius = Float(radius)
        return blur.outputImage?.cropped(to: rect) ?? image
    }
}
