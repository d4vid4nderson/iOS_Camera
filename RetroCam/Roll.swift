import Foundation

/// A roll of film: 36 frames, numbered, named after the film it was loaded with.
/// Persisted, so quitting the app doesn't rewind it. Each roll gets its own album in
/// Photos (see `RollAlbums`).
struct Roll: Codable, Equatable {
    static let length = 36

    var number: Int
    /// Frames exposed so far.
    var frames: Int = 0
    /// Film name of the first frame (the album is named after it).
    var film: String?
    var started: Date?

    var isFinished: Bool { frames >= Self.length }

    /// "Roll 07 · CLASSIC 400"
    var albumTitle: String {
        let n = String(format: "Roll %02d", number)
        guard let film, !film.isEmpty else { return n }
        return "\(n) · \(film)"
    }

    /// Expose a frame. The first frame names the roll after the film loaded.
    mutating func expose(film name: String, at date: Date = Date()) {
        if frames == 0 {
            film = name
            started = date
        }
        frames = min(frames + 1, Self.length)
    }

    /// A frame that failed to develop gives its exposure back.
    mutating func unexpose() {
        frames = max(frames - 1, 0)
        if frames == 0 { film = nil; started = nil }
    }

    /// The next roll, loaded fresh.
    func next() -> Roll { Roll(number: number + 1) }

    // MARK: Persistence

    private static let key = "roll.current"

    static func load(from defaults: UserDefaults = .standard) -> Roll {
        guard let data = defaults.data(forKey: key),
              let roll = try? JSONDecoder().decode(Roll.self, from: data) else { return Roll(number: 1) }
        return roll
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}
