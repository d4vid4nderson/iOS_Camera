import Foundation

/// The films the user can pick: the built-in stocks plus the ones they saved, and any
/// adjustments they've made to a film (remembered per film until they reset it).
///
/// A plain value type so it's easy to test; `CameraModel` owns one and persists it.
struct FilmLibrary: Equatable {
    /// Films the user saved, in the order they were saved.
    private(set) var custom: [FilmStock] = []
    /// Unsaved adjustments, by film id. Absent = the film as shipped (or as saved).
    private(set) var edits: [String: FilmStock] = [:]

    static let maxNameLength = 18

    /// Everything the film picker shows: built-ins first, then the user's own.
    var all: [FilmStock] { FilmStock.all + custom }

    /// The film as shipped or as saved, without adjustments.
    func original(id: String) -> FilmStock? {
        FilmStock.builtIn(id: id) ?? custom.first { $0.id == id }
    }

    /// The film including any adjustments.
    func current(id: String) -> FilmStock? {
        edits[id] ?? original(id: id)
    }

    func isEdited(id: String) -> Bool { edits[id] != nil }

    /// Remember an adjusted film. Adjusting it back to exactly the original clears the edit.
    mutating func setEdit(_ stock: FilmStock) {
        guard let base = original(id: stock.id) else { return }
        edits[stock.id] = stock == base ? nil : stock
    }

    mutating func reset(id: String) { edits[id] = nil }

    /// Save `stock` (with whatever adjustments it has) as a new film of the user's own.
    @discardableResult
    mutating func saveNew(from stock: FilmStock, named name: String,
                          id: String = FilmStock.customPrefix + UUID().uuidString) -> FilmStock {
        var film = stock
        film.id = id
        film.name = Self.cleanName(name)
        let source = original(id: stock.id)?.name ?? stock.name
        film.blurb = "Your film, from \(source)"
        if stock.isCustom, let base = original(id: stock.id) { film.blurb = base.blurb }
        custom.append(film)
        return film
    }

    /// Add a film someone shared (already given its own custom id).
    mutating func add(_ film: FilmStock) {
        guard film.isCustom, original(id: film.id) == nil else { return }
        custom.append(film)
    }

    /// Write the current adjustments into the user's own film `stock.id`.
    mutating func update(_ stock: FilmStock) {
        guard stock.isCustom, let index = custom.firstIndex(where: { $0.id == stock.id }) else { return }
        custom[index] = stock
        edits[stock.id] = nil
    }

    mutating func rename(id: String, to name: String) {
        guard let index = custom.firstIndex(where: { $0.id == id }) else { return }
        custom[index].name = Self.cleanName(name)
        edits[id]?.name = custom[index].name
    }

    mutating func delete(id: String) {
        custom.removeAll { $0.id == id }
        edits[id] = nil
    }

    /// Film names read like film boxes: upper case, short, never empty.
    static func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? "MY FILM" : String(trimmed.prefix(maxNameLength))
    }

    // MARK: Persistence

    private static let customKey = "film.custom"
    private static let editsKey = "film.edits"

    static func load(from defaults: UserDefaults = .standard) -> FilmLibrary {
        var library = FilmLibrary()
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: customKey),
           let films = try? decoder.decode([FilmStock].self, from: data) {
            library.custom = films.filter(\.isCustom)
        }
        if let data = defaults.data(forKey: editsKey),
           let edits = try? decoder.decode([String: FilmStock].self, from: data) {
            // Drop edits for films that no longer exist (e.g. a retired built-in).
            library.edits = edits.filter { library.original(id: $0.key) != nil && $0.key == $0.value.id }
        }
        return library
    }

    func save(to defaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(custom) { defaults.set(data, forKey: Self.customKey) }
        if let data = try? encoder.encode(edits) { defaults.set(data, forKey: Self.editsKey) }
    }
}
