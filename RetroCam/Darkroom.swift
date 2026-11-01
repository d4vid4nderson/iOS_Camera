import CoreImage
import ImageIO
import Photos
import UIKit

enum CameraError: LocalizedError {
    case noCamera
    case setupFailed(String)
    case processingFailed
    case photosAccessDenied

    var errorDescription: String? {
        switch self {
        case .noCamera: return "No camera found."
        case .setupFailed(let what): return "Couldn't set up the camera (\(what))."
        case .processingFailed: return "Couldn't develop that frame."
        case .photosAccessDenied: return "Allow Photos access in Settings to save your shots."
        }
    }
}

/// Develops full-resolution captures and files them in the photo library.
enum Darkroom {
    private static let context = CIContext(options: [.name: "darkroom"])

    struct Print {
        let jpeg: Data
        let thumbnail: UIImage
    }

    static func develop(_ photoData: Data, stock: FilmStock, stampText: String? = nil,
                        finish: PrintFinish = PrintFinish(border: .none, seed: 0)) throws -> Print {
        guard var source = CIImage(data: photoData, options: [.applyOrientationProperty: true]) else {
            throw CameraError.processingFailed
        }

        // Orientation has been baked into the pixels above, so reset the tag
        // in the metadata we carry over (otherwise viewers rotate it twice).
        var metadata = source.properties
        metadata[kCGImagePropertyOrientation as String] = 1
        if var tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            metadata[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        // Pixel dimensions in EXIF would be stale after resizing; the file states its own size.
        if var exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension as String)
            exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension as String)
            metadata[kCGImagePropertyExifDictionary as String] = exif
        }

        // Full-resolution captures (up to 48 MP) are developed at no more than 24 MP:
        // plenty for film-like detail, and half the memory and time.
        let maxPixels: CGFloat = 24_000_000
        let pixels = source.extent.width * source.extent.height
        if pixels > maxPixels {
            let scale = (maxPixels / pixels).squareRoot()
            source = source.applyingFilter("CILanczosScaleTransform",
                                           parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
        }

        let film = FilmLook.apply(stock, to: source, stamp: stampText)
        let developed = PrintBorder.apply(finish.border, to: film, seed: finish.seed).settingProperties(metadata)

        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let jpeg = context.jpegRepresentation(
                of: developed,
                colorSpace: sRGB,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.92])
        else { throw CameraError.processingFailed }

        let thumbScale = 1200 / max(developed.extent.width, developed.extent.height)
        let small = developed.transformed(by: CGAffineTransform(scaleX: thumbScale, y: thumbScale))
        guard let cg = context.createCGImage(small, from: small.extent) else {
            throw CameraError.processingFailed
        }
        return Print(jpeg: jpeg, thumbnail: UIImage(cgImage: cg))
    }

    static func saveToLibrary(_ jpeg: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw CameraError.photosAccessDenied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: jpeg, options: nil)
        }
    }
}
