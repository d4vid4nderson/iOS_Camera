import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// The app's own copy of every roll, so the roll viewer always shows the whole roll —
/// even if a frame is deleted from Photos, or Photos access is limited.
///
///   Application Support/Rolls/007/frame-01.jpg   screen-sharp copy (2048 px long side)
///                                 thumb-01.jpg   grid thumbnail (480 px)
///                                 roll.json      the roll's number, film, dates, develop mode
///                                 films.json     which film each frame was shot on (by film id)
///                                 full-01.jpg    full-resolution frame waiting to develop
///                                                (deleted once it's in Photos)
enum RollStore {
    private static let previewSize = 2048
    private static let thumbSize = 480

    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Rolls", isDirectory: true)
    }

    static func folder(for number: Int) -> URL {
        root.appendingPathComponent(String(format: "%03d", number), isDirectory: true)
    }

    static func frameURL(roll: Int, frame: Int) -> URL {
        folder(for: roll).appendingPathComponent(String(format: "frame-%02d.jpg", frame))
    }

    static func thumbURL(roll: Int, frame: Int) -> URL {
        folder(for: roll).appendingPathComponent(String(format: "thumb-%02d.jpg", frame))
    }

    static func pendingURL(roll: Int, frame: Int) -> URL {
        folder(for: roll).appendingPathComponent(String(format: "full-%02d.jpg", frame))
    }

    /// A frame shot on a develop-later roll that hasn't developed yet.
    static func isPending(roll: Int, frame: Int) -> Bool {
        FileManager.default.fileExists(atPath: pendingURL(roll: roll, frame: frame).path)
    }

    /// Keep the full-resolution frame until its roll develops.
    static func savePending(_ jpeg: Data, roll: Int, frame: Int) throws {
        try FileManager.default.createDirectory(at: folder(for: roll), withIntermediateDirectories: true)
        try jpeg.write(to: pendingURL(roll: roll, frame: frame), options: .atomic)
    }

    static func pendingFrames(of number: Int) -> [Int] {
        frames(of: number).filter { isPending(roll: number, frame: $0) }
    }

    static func clearPending(roll: Int, frame: Int) {
        try? FileManager.default.removeItem(at: pendingURL(roll: roll, frame: frame))
        setPeeking(roll: roll, frame: frame, false)
    }

    private static func peekURL(roll: Int, frame: Int) -> URL {
        folder(for: roll).appendingPathComponent(String(format: "peek-%02d", frame))
    }

    /// A developing frame you chose to look at early (shown in the app only, until its roll
    /// develops).
    static func isPeeking(roll: Int, frame: Int) -> Bool {
        FileManager.default.fileExists(atPath: peekURL(roll: roll, frame: frame).path)
    }

    static func setPeeking(roll: Int, frame: Int, _ on: Bool) {
        if on {
            FileManager.default.createFile(atPath: peekURL(roll: roll, frame: frame).path, contents: Data())
        } else {
            try? FileManager.default.removeItem(at: peekURL(roll: roll, frame: frame))
        }
    }

    /// Record the roll's latest details (e.g. when it was finished).
    static func updateInfo(_ roll: Roll) {
        let folder = folder(for: roll.number)
        guard FileManager.default.fileExists(atPath: folder.path),
              let info = try? JSONEncoder().encode(roll) else { return }
        try? info.write(to: folder.appendingPathComponent("roll.json"), options: .atomic)
    }

    /// Keep a copy of a developed frame. Runs off the main thread.
    static func save(_ jpeg: Data, roll: Roll, frame: Int, filmID: String? = nil) throws {
        let folder = folder(for: roll.number)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let preview = downsample(jpeg, to: previewSize, quality: 0.85),
              let thumb = downsample(jpeg, to: thumbSize, quality: 0.8) else { throw CameraError.processingFailed }
        try preview.write(to: frameURL(roll: roll.number, frame: frame), options: .atomic)
        try thumb.write(to: thumbURL(roll: roll.number, frame: frame), options: .atomic)
        if let info = try? JSONEncoder().encode(roll) {
            try? info.write(to: folder.appendingPathComponent("roll.json"), options: .atomic)
        }
        if let filmID {
            var shotOn = films(of: roll.number)
            shotOn[frame] = filmID
            let named = Dictionary(uniqueKeysWithValues: shotOn.map { (String($0.key), $0.value) })
            if let data = try? JSONEncoder().encode(named) {
                try? data.write(to: folder.appendingPathComponent("films.json"), options: .atomic)
            }
        }
    }

    /// Which film each frame of a roll was shot on (frame number -> film id). Frames shot
    /// before this was recorded aren't listed.
    static func films(of number: Int) -> [Int: String] {
        let url = folder(for: number).appendingPathComponent("films.json")
        guard let data = try? Data(contentsOf: url),
              let named = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: named.compactMap { key, id in Int(key).map { ($0, id) } })
    }

    /// The newest developed frame shot on a film, for its share card. nil if there's none.
    static func latestFrame(filmID: String) -> UIImage? {
        for roll in rolls() {
            let shotOn = films(of: roll.number)
            for frame in frames(of: roll.number).reversed()
            where shotOn[frame] == filmID && !isPending(roll: roll.number, frame: frame) {
                if let image = UIImage(contentsOfFile: frameURL(roll: roll.number, frame: frame).path) { return image }
            }
        }
        return nil
    }

    /// Remove the app's copy of a roll: frames, thumbnails, undeveloped frames, details.
    static func delete(roll number: Int) throws {
        let folder = folder(for: number)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    /// Frame numbers stored for a roll, in order.
    static func frames(of number: Int) -> [Int] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder(for: number).path)) ?? []
        return names.compactMap { name -> Int? in
            guard name.hasPrefix("frame-"), name.hasSuffix(".jpg") else { return nil }
            return Int(name.dropFirst(6).dropLast(4))
        }.sorted()
    }

    /// Rolls that have at least one stored frame, newest first.
    static func rolls() -> [Roll] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.compactMap { name -> Roll? in
            guard let number = Int(name), !frames(of: number).isEmpty else { return nil }
            let info = folder(for: number).appendingPathComponent("roll.json")
            if let data = try? Data(contentsOf: info), let roll = try? JSONDecoder().decode(Roll.self, from: data) {
                return roll
            }
            return Roll(number: number)
        }.sorted { $0.number > $1.number }
    }

    /// The newest frame's thumbnail, for the button next to the shutter at launch.
    static func latestThumbnail() -> UIImage? {
        for roll in rolls() {
            if let last = frames(of: roll.number).last(where: { !isPending(roll: roll.number, frame: $0) }),
               let image = UIImage(contentsOfFile: thumbURL(roll: roll.number, frame: last).path) {
                return image
            }
        }
        return nil
    }

    /// Re-encode `jpeg` with its long side at most `maxPixels`, without decoding it full size.
    private static func downsample(_ jpeg: Data, to maxPixels: Int, quality: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
