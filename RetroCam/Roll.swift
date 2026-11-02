import Foundation

/// When a roll's frames appear: straight away, when the roll is finished, or the
/// morning after it's finished, like dropping film at a lab.
enum DevelopMode: String, Codable, CaseIterable, Identifiable {
    case instant, rollEnd, nextMorning

    var id: String { rawValue }

    var label: String {
        switch self {
        case .instant: return "INSTANT"
        case .rollEnd: return "ROLL END"
        case .nextMorning: return "NEXT MORNING"
        }
    }

    /// Hour of the morning the lab is open.
    static let labHour = 9

    /// When a roll shot in this mode and finished at `finished` is developed.
    /// nil = not yet (the roll isn't finished).
    func readyDate(finished: Date?, calendar: Calendar = .current) -> Date? {
        switch self {
        case .instant:
            return .distantPast
        case .rollEnd:
            return finished
        case .nextMorning:
            guard let finished else { return nil }
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: finished))!
            return calendar.date(bySettingHour: Self.labHour, minute: 0, second: 0, of: nextDay)
        }
    }
}

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
    /// How this roll develops (fixed by its first frame). nil = instant (older rolls).
    var developMode: DevelopMode?
    /// When the last frame was shot, or the roll was finished early.
    var finishedAt: Date?
    /// A name you gave the roll ("Beach day"). nil = just its number.
    var name: String?

    static let maxNameLength = 24

    var develop: DevelopMode { developMode ?? .instant }

    /// When this roll's frames appear. nil = not finished yet.
    func readyDate(calendar: Calendar = .current) -> Date? {
        develop.readyDate(finished: finishedAt, calendar: calendar)
    }

    func isDeveloped(at now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let ready = readyDate(calendar: calendar) else { return false }
        return ready <= now
    }

    var isFinished: Bool { frames >= Self.length }

    /// Part-shot with frames left: it can go back in the camera to carry on shooting, even
    /// if it was finished early (loading it opens it again).
    var isOpen: Bool { frames > 0 && frames < Self.length }

    /// Back in the camera: a roll finished early carries on, and develops again when it's
    /// finished next.
    mutating func reopen() {
        guard frames < Self.length else { return }
        finishedAt = nil
    }

    /// A number for a new roll that no roll already has.
    static func freshNumber(after existing: [Int]) -> Int { (existing.max() ?? 0) + 1 }

    /// The roll numbered after this one, loaded fresh.
    func next() -> Roll { Roll(number: number + 1) }

    /// "Roll 07"
    var numberTitle: String { String(format: "Roll %02d", number) }

    /// The roll's name if you gave it one, else "Roll 07".
    var title: String { name ?? numberTitle }

    /// "Roll 07 · Beach day" for a named roll, else "Roll 07 · CLASSIC 400".
    var albumTitle: String {
        if let name { return "\(numberTitle) · \(name)" }
        guard let film, !film.isEmpty else { return numberTitle }
        return "\(numberTitle) · \(film)"
    }

    /// A typed roll name, tidied: trimmed, at most 24 characters; empty = no name.
    static func cleanName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxNameLength))
    }

    /// Expose a frame. The first frame names the roll after the film loaded.
    mutating func expose(film name: String, develop mode: DevelopMode = .instant, at date: Date = Date()) {
        if frames == 0 {
            film = name
            started = date
            developMode = mode
        }
        frames = min(frames + 1, Self.length)
        if frames == Self.length { finishedAt = date }
    }

    /// Finish before frame 36 (the rest of the roll stays blank).
    mutating func finish(at date: Date = Date()) {
        if finishedAt == nil { finishedAt = date }
    }

    /// A frame that failed to develop gives its exposure back.
    mutating func unexpose() {
        frames = max(frames - 1, 0)
        finishedAt = nil
        if frames == 0 { film = nil; started = nil; developMode = nil }
    }


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
