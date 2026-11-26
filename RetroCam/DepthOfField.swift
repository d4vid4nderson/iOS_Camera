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

    /// `image` with everything away from the focus distance blurred, as the lens would at
    /// `fNumber`. `disparity` covers the same view as `image`, at any size.
    static func apply(to image: CIImage, disparity: CIImage, focus: CGFloat,
                      fNumber: Double, focalLength: Double) -> CIImage {
        let extent = image.extent
        guard fNumber < Aperture.closed, fNumber > 0, focalLength > 0,
              extent.width > 1, extent.height > 1, !extent.isInfinite,
              disparity.extent.width > 0, disparity.extent.height > 0 else { return image }
        let long = max(extent.width, extent.height)
        // Blur radius (fraction of the long side) per unit of disparity away from focus,
        // then as a share of the largest radius: that's what the mask holds, 0...1.
        let perUnit = 0.5 * gain * CGFloat(focalLength * focalLength) / (CGFloat(fNumber) * frame)
        let slope = perUnit / maxRadius
        let fitted = fit(disparity, to: extent)

        // slope · (|d - focus| - tolerance), built as the larger of the two signed sides.
        func side(_ sign: CGFloat) -> CIImage {
            let k = sign * slope
            let row = CIVector(x: k, y: 0, z: 0, w: 0)
            let bias = -k * focus - slope * tolerance
            return fitted.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": row, "inputGVector": row, "inputBVector": row,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 1),
            ])
        }
        let mask = side(1)
            .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: side(-1)])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
            ])
            // The map is far coarser than the picture: soften its steps.
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(long * 0.004))
            .cropped(to: extent)

        let blur = CIFilter.maskedVariableBlur()
        blur.inputImage = image.clampedToExtent()
        blur.mask = mask
        blur.radius = Float(maxRadius * long)
        return blur.outputImage?.cropped(to: extent) ?? image
    }
}
