import UIKit

/// Sharing a roll as a link: its developed frames are uploaded to the share server
/// (server/), where anyone with the link can see them for 30 days, in Film Exposures or on
/// the web. You can unshare any time, which deletes them.
///
/// Signed in, a roll can also go on your public profile, where it stays (and doesn't
/// expire) until you make it private, which deletes it from the server.
enum RollShare {
    static let lifetimeDays = 30

    enum ShareError: LocalizedError {
        case notConfigured
        case server(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Roll sharing isn't set up yet."
            case .server(let message): return message
            }
        }
    }

    /// This phone's sharing details for a roll it shared (kept in the roll's folder).
    struct Record: Codable, Equatable {
        var id: String
        var token: String
        var url: URL
        var expiresAt: Date
        /// On your public profile.
        var isPublic: Bool?
        /// The account it belongs to, when it was shared signed in.
        var owner: String?
        /// The roll's frame numbers in the order they were uploaded (frame-01, -02…).
        var frames: [Int]?

        var onProfile: Bool { isPublic == true }
    }

    /// A roll someone shared, as the app's viewer needs it.
    struct RemoteRoll: Decodable {
        struct Film: Decodable { var name: String?; var code: String? }
        struct Sharer: Decodable { var id: String?; var name: String?; var avatar: URL?; var profile: URL? }
        var id: String
        var title: String
        var film: Film
        var sharer: Sharer
        var shotAt: String?
        var frames: [URL]
        /// The cover frame, numbered from 1.
        var cover: Int?
        var expiresAt: String?
        var `public`: Bool?
    }

    /// Someone's public profile.
    struct RemoteProfile: Decodable {
        struct RollTile: Decodable, Identifiable {
            var id: String
            var title: String
            var film: String?
            var frames: Int
            var shotAt: String?
            var cover: URL
        }
        var id: String
        var name: String?
        var avatar: URL?
        var url: URL
        var rolls: [RollTile]
    }

    /// Someone who liked a frame or a roll: their name and headshot, to open their profile.
    struct Liker: Decodable, Equatable, Identifiable {
        var id: String
        var name: String?
        var avatar: URL?

        @MainActor static var me: Liker? {
            Account.shared.me.map { Liker(id: $0.id, name: $0.name, avatar: $0.avatar) }
        }
    }

    /// Likes on a roll's frames (numbered from 1) and on the roll itself (frame 0, `Likes.roll`),
    /// which of them are yours, and who liked each one (you first).
    struct Likes: Decodable, Equatable {
        static let roll = 0

        var counts: [String: Int]
        var mine: [Int]
        var likers: [String: [Liker]]?

        func count(_ frame: Int) -> Int { counts[String(frame)] ?? 0 }
        func isMine(_ frame: Int) -> Bool { mine.contains(frame) }
        func people(_ frame: Int) -> [Liker] { likers?[String(frame)] ?? [] }

        mutating func set(_ frame: Int, liked: Bool, count: Int? = nil, me: Liker? = nil) {
            let was = isMine(frame)
            if liked, !was { mine.append(frame) }
            if !liked { mine.removeAll { $0 == frame } }
            counts[String(frame)] = count ?? max(0, self.count(frame) + (liked == was ? 0 : liked ? 1 : -1))
            if let me {
                var list = people(frame).filter { $0.id != me.id }
                if liked { list.insert(me, at: 0) }
                var all = likers ?? [:]
                all[String(frame)] = list
                likers = all
            }
        }
    }

    // MARK: Who's sharing, and who you've blocked

    private static let sharerKey = "share.sharerID"
    private static let blockedKey = "share.blocked"

    /// Who to block for this phone's shares: your account, or an anonymous id when you're
    /// signed out.
    static var sharerID: String {
        if let id = Account.storedID { return id }
        if let id = UserDefaults.standard.string(forKey: sharerKey) { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: sharerKey)
        return id
    }

    static func isBlocked(_ sharer: String?) -> Bool {
        guard let sharer else { return false }
        return (UserDefaults.standard.stringArray(forKey: blockedKey) ?? []).contains(sharer)
    }

    static func block(_ sharer: String?) {
        guard let sharer else { return }
        var blocked = UserDefaults.standard.stringArray(forKey: blockedKey) ?? []
        if !blocked.contains(sharer) { blocked.append(sharer) }
        UserDefaults.standard.set(blocked, forKey: blockedKey)
    }

    // MARK: Your shared rolls

    private static func recordURL(_ roll: Int) -> URL {
        RollStore.folder(for: roll).appendingPathComponent("share.json")
    }

    /// The live share of a roll, if it has one (nil once it has expired).
    static func record(for roll: Int, now: Date = Date()) -> Record? {
        guard let data = try? Data(contentsOf: recordURL(roll)),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.expiresAt > now else { return nil }
        return record
    }

    private static func save(_ record: Record, roll: Int) {
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: recordURL(roll), options: .atomic)
        }
    }

    /// After an account is deleted, forget the shares the server deleted with it.
    static func forgetShares(ownedBy id: String) {
        for roll in RollStore.rolls() {
            guard let data = try? Data(contentsOf: recordURL(roll.number)),
                  let record = try? JSONDecoder().decode(Record.self, from: data),
                  record.owner == id else { continue }
            try? FileManager.default.removeItem(at: recordURL(roll.number))
        }
    }

    /// Upload a roll's developed frames and its card; returns the share and the card.
    static func share(roll: Roll, frames: [Int], film: FilmStock?, profile: Profile,
                      progress: @escaping @MainActor (Int, Int) -> Void) async throws -> (Record, UIImage?) {
        guard let base = ShareLinks.base else { throw ShareError.notConfigured }
        guard !frames.isEmpty else { throw ShareError.server("There are no developed frames to share yet.") }
        let title = roll.title
        let showProfile = profile.showOnCards && !profile.isEmpty

        var filmInfo: [String: Any] = [:]
        if let name = film?.name ?? roll.film { filmInfo["name"] = name }
        if let film, let link = FilmCode.url(for: film) { filmInfo["code"] = link.lastPathComponent }
        var sharer: [String: Any] = ["id": sharerID]
        if showProfile { sharer["name"] = profile.name }
        var body: [String: Any] = ["frames": frames.count, "title": title, "film": filmInfo, "sharer": sharer]
        if let cover = roll.cover, let index = frames.firstIndex(of: cover) { body["cover"] = index + 1 }
        if let started = roll.started { body["shotAt"] = started.formatted(.dateTime.month(.abbreviated).day().year()) }

        let account = Account.sessionToken
        let created = try await send(base.appendingPathComponent("api/rolls"), method: "POST", account: account, json: body)
        guard let info = try? JSONSerialization.jsonObject(with: created) as? [String: Any],
              let id = info["id"] as? String, let token = info["token"] as? String,
              let link = (info["url"] as? String).flatMap(URL.init(string:)) else {
            throw ShareError.server("The share server sent back something unexpected.")
        }
        let expires = (info["expiresAt"] as? String).flatMap(parseDate)
            ?? Date().addingTimeInterval(Double(lifetimeDays) * 86_400)
        let record = Record(id: id, token: token, url: link, expiresAt: expires, isPublic: false,
                            owner: account == nil ? nil : Account.storedID, frames: frames)
        let files = base.appendingPathComponent("api/rolls").appendingPathComponent(id)

        do {
            let total = frames.count + 1
            for (i, frame) in frames.enumerated() {
                let data = try Data(contentsOf: RollStore.frameURL(roll: roll.number, frame: frame))
                _ = try await send(files.appendingPathComponent(String(format: "frame-%02d.jpg", i + 1)),
                                   method: "PUT", token: token, body: data, type: "image/jpeg")
                await progress(i + 1, total)
            }
            let thumbs = cardFrames(roll, from: frames).compactMap { UIImage(contentsOfFile: RollStore.thumbURL(roll: roll.number, frame: $0).path) }
            let cardSharer = showProfile ? FilmCodeCard.Sharer(name: profile.name, avatar: profile.photo) : nil
            let card = RollCard.render(title: title, filmName: film?.name ?? roll.film, frameCount: frames.count,
                                       frames: thumbs, url: link, sharer: cardSharer)
            if let jpeg = card?.jpegData(compressionQuality: 0.86) {
                _ = try await send(files.appendingPathComponent("card.jpg"), method: "PUT", token: token, body: jpeg, type: "image/jpeg")
            }
            if showProfile, let avatar = profile.photo?.jpegData(compressionQuality: 0.85) {
                _ = try await send(files.appendingPathComponent("avatar.jpg"), method: "PUT", token: token, body: avatar, type: "image/jpeg")
            }
            _ = try await send(files.appendingPathComponent("publish"), method: "POST", token: token)
            await progress(total, total)

            save(record, roll: roll.number)
            return (record, card)
        } catch {
            // Don't leave a half-uploaded roll behind.
            _ = try? await send(files, method: "DELETE", token: token)
            throw error
        }
    }

    /// Up to 9 frames for the roll's card, its cover first.
    static func cardFrames(_ roll: Roll, from frames: [Int]) -> [Int] {
        guard let cover = roll.cover, frames.contains(cover) else { return Array(frames.prefix(9)) }
        return Array(([cover] + frames.filter { $0 != cover }).prefix(9))
    }

    /// The roll's cover on the server, if it's shared: the frame you picked (or the first).
    /// Rolls shared before covers existed don't know their upload order, so they're left.
    static func updateCover(of roll: Roll) async throws {
        guard let base = ShareLinks.base, let record = record(for: roll.number), let uploaded = record.frames else { return }
        let index = roll.cover.flatMap { uploaded.firstIndex(of: $0) }.map { $0 + 1 } ?? 1
        _ = try await send(base.appendingPathComponent("api/rolls").appendingPathComponent(record.id).appendingPathComponent("cover"),
                           method: "POST", token: record.token, json: ["cover": index])
    }

    /// Delete a shared roll from the server (and forget the link).
    static func unshare(roll: Int) async throws {
        guard let data = try? Data(contentsOf: recordURL(roll)),
              let record = try? JSONDecoder().decode(Record.self, from: data) else { return }
        if let base = ShareLinks.base, record.expiresAt > Date() {
            _ = try await send(base.appendingPathComponent("api/rolls").appendingPathComponent(record.id),
                               method: "DELETE", token: record.token)
        }
        try? FileManager.default.removeItem(at: recordURL(roll))
    }

    enum ProfileError: LocalizedError {
        case signIn, terms
        var errorDescription: String? {
            switch self {
            case .signIn: return "Sign in with Apple in your profile to put rolls on it."
            case .terms: return "Agree to the rules for public rolls first."
            }
        }
    }

    /// Put a roll on your public profile: uploads it first if it isn't shared yet. A roll
    /// you shared before signing in is claimed with its token.
    static func makePublic(roll: Roll, film: FilmStock?, profile: Profile,
                           progress: @escaping @MainActor (Int, Int) -> Void) async throws -> Record {
        guard let base = ShareLinks.base else { throw ShareError.notConfigured }
        guard let account = Account.sessionToken else { throw ProfileError.signIn }
        var record: Record
        if let existing = Self.record(for: roll.number) {
            record = existing
        } else {
            let frames = RollStore.frames(of: roll.number).filter { !RollStore.isPending(roll: roll.number, frame: $0) }
            record = try await share(roll: roll, frames: frames, film: film, profile: profile, progress: progress).0
        }
        do {
            _ = try await send(base.appendingPathComponent("api/rolls").appendingPathComponent(record.id).appendingPathComponent("visibility"),
                               method: "POST", token: record.token, account: account, json: ["public": true])
        } catch let error as ShareAPI.HTTPError where error.status == 403 && error.message == "terms" {
            throw ProfileError.terms
        }
        record.isPublic = true
        record.owner = Account.storedID
        record.expiresAt = .distantFuture
        save(record, roll: roll.number)
        return record
    }

    // MARK: Rolls still being shot

    /// A roll's developed frames: the ones that can be shared (not ones still developing,
    /// even if you've peeked at them).
    static func developedFrames(of roll: Int) -> [Int] {
        RollStore.frames(of: roll).filter { !RollStore.isPending(roll: roll, frame: $0) }
    }

    private static func waitURL(_ roll: Int) -> URL {
        RollStore.folder(for: roll).appendingPathComponent("profile-when-developed")
    }

    /// A roll you put on your profile before any of it had developed: it goes on when its
    /// first frames develop.
    static func waitsForProfile(_ roll: Int) -> Bool {
        FileManager.default.fileExists(atPath: waitURL(roll).path)
    }

    static func setWaitsForProfile(_ roll: Int, _ on: Bool) {
        if on {
            try? FileManager.default.createDirectory(at: RollStore.folder(for: roll), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: waitURL(roll).path, contents: Data())
        } else {
            try? FileManager.default.removeItem(at: waitURL(roll))
        }
    }

    private static let syncLock = NSLock()
    private static var syncing: Task<Void, Never>?

    /// Bring a roll's share up to date after frames develop, one at a time: frames
    /// developed since it was shared are added to it (and its card redrawn), and a roll
    /// waiting to go on your profile goes on it once it has developed frames.
    static func syncSoon(roll: Roll, film: FilmStock?, profile: Profile) {
        syncLock.lock()
        defer { syncLock.unlock() }
        let previous = syncing
        syncing = Task {
            await previous?.value
            await sync(roll: roll, film: film, profile: profile)
        }
    }

    private static func sync(roll: Roll, film: FilmStock?, profile: Profile) async {
        let developed = developedFrames(of: roll.number)
        guard !developed.isEmpty, let base = ShareLinks.base else { return }
        guard var record = record(for: roll.number) else {
            guard waitsForProfile(roll.number), Account.sessionToken != nil else { return }
            if (try? await makePublic(roll: roll, film: film, profile: profile, progress: { _, _ in })) != nil {
                setWaitsForProfile(roll.number, false)
            }
            return
        }
        // Rolls shared before the upload order was kept can't be added to.
        guard var uploaded = record.frames else { return }
        let new = developed.filter { !uploaded.contains($0) }
        guard !new.isEmpty else { return }
        let files = base.appendingPathComponent("api/rolls").appendingPathComponent(record.id)
        for frame in new where uploaded.count < Roll.length {
            guard let data = try? Data(contentsOf: RollStore.frameURL(roll: roll.number, frame: frame)) else { break }
            do {
                _ = try await send(files.appendingPathComponent(String(format: "frame-%02d.jpg", uploaded.count + 1)),
                                   method: "PUT", token: record.token, body: data, type: "image/jpeg")
            } catch {
                break   // try again after the next frame develops
            }
            uploaded.append(frame)
            record.frames = uploaded
            save(record, roll: roll.number)
        }
        if let card = card(for: roll, record: record, film: film, profile: profile)?.jpegData(compressionQuality: 0.86) {
            _ = try? await send(files.appendingPathComponent("card.jpg"), method: "PUT", token: record.token, body: card, type: "image/jpeg")
        }
    }

    // MARK: Profiles and likes

    static func fetchProfile(id: String) async throws -> RemoteProfile {
        guard let base = ShareLinks.base else { throw ShareError.notConfigured }
        let data = try await send(base.appendingPathComponent("u").appendingPathComponent(id).appendingPathComponent("profile.json"),
                                  method: "GET", notFound: "There's no profile here any more.")
        do {
            return try JSONDecoder().decode(RemoteProfile.self, from: data)
        } catch {
            throw ShareError.server("This profile couldn't be read.")
        }
    }

    static func likes(id: String) async throws -> Likes {
        guard let base = ShareLinks.base else { throw ShareError.notConfigured }
        let data = try await send(base.appendingPathComponent("api/rolls").appendingPathComponent(id).appendingPathComponent("likes"),
                                  method: "GET", account: Account.sessionToken)
        return (try? JSONDecoder().decode(Likes.self, from: data)) ?? Likes(counts: [:], mine: [])
    }

    /// Like or unlike a frame (numbered from 1), or the whole roll (`Likes.roll`); returns
    /// its like count.
    static func like(id: String, frame: Int, _ on: Bool) async throws -> Int {
        guard let base = ShareLinks.base else { throw ShareError.notConfigured }
        guard let account = Account.sessionToken else { throw ProfileError.signIn }
        let roll = base.appendingPathComponent("api/rolls").appendingPathComponent(id)
        let url = frame == Likes.roll
            ? roll.appendingPathComponent("like")
            : roll.appendingPathComponent("frames").appendingPathComponent(String(frame)).appendingPathComponent("like")
        let data = try await send(url, method: on ? "PUT" : "DELETE", account: account)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["count"] as? Int ?? 0
    }

    /// The card for a roll you've already shared, to share the link again.
    static func card(for roll: Roll, record: Record, film: FilmStock?, profile: Profile) -> UIImage? {
        let frames = RollStore.frames(of: roll.number).filter { !RollStore.isPending(roll: roll.number, frame: $0) }
        let thumbs = cardFrames(roll, from: frames).compactMap { UIImage(contentsOfFile: RollStore.thumbURL(roll: roll.number, frame: $0).path) }
        let showProfile = profile.showOnCards && !profile.isEmpty
        return RollCard.render(title: roll.title, filmName: film?.name ?? roll.film,
                               frameCount: frames.count, frames: Array(thumbs), url: record.url,
                               sharer: showProfile ? FilmCodeCard.Sharer(name: profile.name, avatar: profile.photo) : nil)
    }

    // MARK: Someone else's roll

    static func fetch(id: String) async throws -> RemoteRoll {
        guard let base = ShareLinks.base else { throw ShareError.notConfigured }
        let data = try await send(base.appendingPathComponent("r").appendingPathComponent(id).appendingPathComponent("roll.json"),
                                  method: "GET", notFound: "This roll has expired or was unshared.")
        do {
            return try JSONDecoder().decode(RemoteRoll.self, from: data)
        } catch {
            throw ShareError.server("This roll couldn't be read.")
        }
    }

    static func report(id: String, reason: String) async throws {
        guard let base = ShareLinks.base else { throw ShareError.notConfigured }
        _ = try await send(base.appendingPathComponent("api/rolls").appendingPathComponent(id).appendingPathComponent("report"),
                           method: "POST", json: ["reason": reason])
    }

    private static func send(_ url: URL, method: String, token: String? = nil, account: String? = nil,
                             json: [String: Any]? = nil, body: Data? = nil, type: String? = nil,
                             notFound: String? = nil) async throws -> Data {
        try await ShareAPI.send(url, method: method, token: token, account: account, json: json,
                                body: body, type: type, notFound: notFound)
    }

    private static func parseDate(_ string: String) -> Date? { ShareAPI.parseDate(string) }
}
