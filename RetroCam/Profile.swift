import UIKit
import Vision

/// Who's sharing: a headshot and a name for share cards ("@david", "David Anderson").
/// Kept on this phone only; nothing is uploaded.
struct Profile: Equatable {
    var name: String = ""
    var photo: UIImage?
    /// Put the headshot and name on share cards.
    var showOnCards: Bool = true

    static let maxNameLength = 24
    private static let nameKey = "profile.name"
    private static let showKey = "profile.showOnCards"
    private static let headshotSize: CGFloat = 600

    var isEmpty: Bool { name.isEmpty && photo == nil }

    static var photoURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("profile.jpg")
    }

    static func load(from defaults: UserDefaults = .standard) -> Profile {
        Profile(name: defaults.string(forKey: nameKey) ?? "",
                photo: UIImage(contentsOfFile: photoURL.path),
                showOnCards: defaults.object(forKey: showKey) as? Bool ?? true)
    }

    func saveSettings(to defaults: UserDefaults = .standard) {
        defaults.set(name, forKey: Self.nameKey)
        defaults.set(showOnCards, forKey: Self.showKey)
    }

    static func cleanName(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
    }

    /// Crop a picked photo to a square headshot around the largest face (or the upper
    /// middle if there's no face), save it, and return it.
    static func saveHeadshot(from data: Data) -> UIImage? {
        guard let picked = UIImage(data: data), let headshot = headshot(from: picked),
              let jpeg = headshot.jpegData(compressionQuality: 0.88) else { return nil }
        try? FileManager.default.createDirectory(at: photoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? jpeg.write(to: photoURL, options: .atomic)) != nil else { return nil }
        return headshot
    }

    static func removeHeadshot() {
        try? FileManager.default.removeItem(at: photoURL)
    }

    private static func headshot(from picked: UIImage) -> UIImage? {
        // Draw upright (bakes in the orientation) at a sensible size first.
        let longSide = max(picked.size.width, picked.size.height)
        guard longSide > 0 else { return nil }
        let scale = min(1, 1600 / longSide)
        let uprightSize = CGSize(width: (picked.size.width * scale).rounded(), height: (picked.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let upright = UIGraphicsImageRenderer(size: uprightSize, format: format).image { _ in
            picked.draw(in: CGRect(origin: .zero, size: uprightSize))
        }
        guard let cg = upright.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)

        // Largest face, in pixels with a top-left origin.
        var face: CGRect?
        let request = VNDetectFaceRectanglesRequest()
        if (try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])) != nil,
           let best = request.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) {
            let b = best.boundingBox
            face = CGRect(x: b.minX * w, y: (1 - b.maxY) * h, width: b.width * w, height: b.height * h)
        }

        let maxSide = min(w, h)
        var crop: CGRect
        if let face {
            let side = min(maxSide, max(face.width, face.height) * 2.4)
            crop = CGRect(x: face.midX - side / 2, y: face.midY - side * 0.45, width: side, height: side)
        } else {
            crop = CGRect(x: (w - maxSide) / 2, y: (h - maxSide) * 0.3, width: maxSide, height: maxSide)
        }
        crop.origin.x = min(max(crop.minX, 0), w - crop.width)
        crop.origin.y = min(max(crop.minY, 0), h - crop.height)

        let out = CGSize(width: headshotSize, height: headshotSize)
        return UIGraphicsImageRenderer(size: out, format: format).image { _ in
            let k = headshotSize / crop.width
            upright.draw(in: CGRect(x: -crop.minX * k, y: -crop.minY * k, width: w * k, height: h * k))
        }
    }
}
