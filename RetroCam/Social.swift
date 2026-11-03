import SwiftUI

private extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: Who sees a roll

/// Who a shared roll is for. The server checks it on every request, photos included.
enum Audience: String, CaseIterable, Identifiable, Codable {
    /// Only you: the roll isn't on the server at all.
    case onlyMe = "private"
    /// The people you pick, in their SHARED WITH YOU.
    case people
    /// The followers you approved, on your profile and in their feed.
    case followers
    /// Everyone, on your profile.
    case everyone = "public"
    /// Anyone with the link, for 30 days (sharing a roll as a link).
    case link

    var id: String { rawValue }

    /// The choices in the audience menu (a link share is made from the share button).
    static let choices: [Audience] = [.onlyMe, .people, .followers, .everyone]

    var label: String {
        switch self {
        case .onlyMe: return "PRIVATE"
        case .people: return "SPECIFIC PEOPLE"
        case .followers: return "FOLLOWERS"
        case .everyone: return "PUBLIC"
        case .link: return "ANYONE WITH THE LINK"
        }
    }

    var icon: String {
        switch self {
        case .onlyMe: return "lock.fill"
        case .people: return "person.2.fill"
        case .followers: return "person.3.fill"
        case .everyone: return "globe"
        case .link: return "link"
        }
    }

    var detail: String {
        switch self {
        case .onlyMe: return "Only on this phone."
        case .people: return "Only the people you pick."
        case .followers: return "Followers you approved."
        case .everyone: return "Anyone, on your profile."
        case .link: return "Anyone with the link, for 30 days."
        }
    }

    /// Shown to others on your profile or in an inbox: needs the rules, and doesn't expire.
    var isShared: Bool { self == .people || self == .followers || self == .everyone }
}

// MARK: Talking to the server

enum Social {
    struct Person: Decodable, Identifiable, Hashable {
        var id: String
        var handle: String?
        var name: String?
        var avatar: URL?
        /// How you stand with them, in search results: "none", "requested" or "following".
        var status: String?

        var title: String {
            let name = name?.trimmingCharacters(in: .whitespaces) ?? ""
            return name.isEmpty ? (handle.map { "@\($0)" } ?? "SOMEONE") : name
        }
    }

    /// A roll in your feed or inbox.
    struct RollTile: Decodable, Identifiable {
        var id: String
        var title: String
        var film: String?
        var frames: Int
        var cover: URL
        var audience: String?
        var by: Person?
        var sharedAt: String?
    }

    private struct People: Decodable { var people: [Person] }
    private struct Rolls: Decodable { var rolls: [RollTile] }

    enum SocialError: LocalizedError {
        case signIn
        var errorDescription: String? { "Sign in from your profile first." }
    }

    private static func call(_ path: String, method: String = "GET", query: [URLQueryItem] = [], json: [String: Any]? = nil) async throws -> Data {
        guard let base = ShareLinks.base else { throw RollShare.ShareError.notConfigured }
        guard let account = Account.sessionToken else { throw SocialError.signIn }
        var url = base.appendingPathComponent(path)
        if !query.isEmpty, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            parts.queryItems = query
            url = parts.url ?? url
        }
        return try await ShareAPI.send(url, method: method, account: account, json: json)
    }

    static func search(_ text: String) async throws -> [Person] {
        let data = try await call("api/users/search", query: [URLQueryItem(name: "q", value: text)])
        return (try? JSONDecoder().decode(People.self, from: data).people) ?? []
    }

    /// Ask to follow someone (they approve it), or stop following / cancel the request.
    /// Returns the new status: "requested", "following" or "none".
    static func follow(_ id: String, _ on: Bool) async throws -> String {
        let data = try await call("api/users/\(id)/follow", method: on ? "POST" : "DELETE")
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["status"] as? String ?? (on ? "requested" : "none")
    }

    static func requests() async throws -> [Person] {
        try JSONDecoder().decode(People.self, from: try await call("api/me/requests")).people
    }

    static func answer(_ id: String, accept: Bool) async throws {
        _ = try await call("api/me/requests/\(id)", method: "POST", json: ["accept": accept])
    }

    static func removeFollower(_ id: String) async throws {
        _ = try await call("api/me/followers/\(id)", method: "DELETE")
    }

    /// "followers" or "following" of someone.
    static func list(_ id: String, _ which: String) async throws -> [Person] {
        try JSONDecoder().decode(People.self, from: try await call("api/users/\(id)/\(which)")).people
    }

    static func block(_ id: String, _ on: Bool) async throws {
        _ = try await call("api/users/\(id)/block", method: on ? "POST" : "DELETE")
    }

    static func feed() async throws -> [RollTile] {
        try JSONDecoder().decode(Rolls.self, from: try await call("api/feed")).rolls
    }

    static func inbox() async throws -> [RollTile] {
        try JSONDecoder().decode(Rolls.self, from: try await call("api/me/inbox")).rolls
    }
}

// MARK: Pieces

/// Someone's headshot, or their initial.
struct PersonAvatar: View {
    let person: Social.Person
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url = person.avatar {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color(white: 0.2) }
            } else {
                ZStack {
                    Color(white: 0.22)
                    Text(String(person.title.first(where: { $0.isLetter || $0.isNumber }) ?? "·").uppercased())
                        .font(.system(size: size * 0.42, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// A person in a list: headshot, name and @handle, with whatever buttons the list needs.
struct PersonRow<Trailing: View>: View {
    let person: Social.Person
    var onOpen: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Button { onOpen?() } label: {
                HStack(spacing: 12) {
                    PersonAvatar(person: person, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.title.uppercased()).font(.mono(12, .bold)).foregroundStyle(.white).lineLimit(1)
                        if let handle = person.handle {
                            Text("@\(handle)").font(.mono(10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onOpen == nil)
            trailing()
        }
        .padding(.vertical, 5)
    }
}

/// A small capsule button, in the app's style.
struct SocialChip: View {
    let text: String
    var selected = false
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.mono(10, .bold))
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Capsule().fill(selected ? accent.opacity(0.18) : Color(white: 0.15)))
                .overlay(Capsule().stroke(selected ? accent : .clear, lineWidth: 1))
                .foregroundStyle(selected ? accent : .white)
        }
        .buttonStyle(.plain)
    }
}

/// FOLLOW / REQUESTED / FOLLOWING for someone, with what tapping it does.
struct FollowButton: View {
    let id: String
    @Binding var status: String
    let accent: Color
    var onError: (String) -> Void = { _ in }
    @State private var working = false

    var body: some View {
        SocialChip(text: working ? "…" : label, selected: status == "none", accent: accent) {
            guard !working else { return }
            working = true
            let on = status == "none"
            Task {
                do {
                    status = try await Social.follow(id, on)
                } catch {
                    onError(error.localizedDescription.uppercased())
                }
                working = false
            }
        }
        .accessibilityLabel(status == "following" ? "Following. Tap to unfollow" : status == "requested" ? "Requested. Tap to cancel" : "Follow")
    }

    private var label: String {
        switch status {
        case "following": return "FOLLOWING"
        case "requested": return "REQUESTED"
        default: return "FOLLOW"
        }
    }
}

// MARK: The social screen

/// People and the rolls they share with you: your feed, rolls shared with you, follow
/// requests and search. Opened from your profile.
struct SocialView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case feed, shared, requests, find
        var id: String { rawValue }
        var label: String {
            switch self {
            case .feed: return "FOLLOWING"
            case .shared: return "SHARED WITH YOU"
            case .requests: return "REQUESTS"
            case .find: return "FIND PEOPLE"
            }
        }
    }

    @ObservedObject var camera: CameraModel
    let accent: Color
    @State var tab: Tab
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var account = Account.shared

    @State private var feed: [Social.RollTile]?
    @State private var shared: [Social.RollTile]?
    @State private var requests: [Social.Person]?
    @State private var query = ""
    @State private var results: [Social.Person] = []
    @State private var statuses: [String: String] = [:]
    @State private var note: String?
    @State private var opening: OpenSocialRoll?
    @State private var person: IncomingUser?

    var body: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("PEOPLE").font(.mono(15, .bold)).foregroundStyle(accent)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color(white: 0.16)))
                    }
                    .foregroundStyle(.white)
                    .accessibilityLabel("Close")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Tab.allCases) { t in
                            SocialChip(text: t == .requests && (requests?.count ?? 0) > 0 ? "REQUESTS · \(requests!.count)" : t.label,
                                       selected: tab == t, accent: accent) { tab = t }
                        }
                    }
                }
                if account.me?.handle == nil {
                    Text("Choose a @handle on your profile so people can find you and you can follow them.")
                        .font(.mono(10)).foregroundStyle(accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note {
                    Text(note).font(.mono(10, .semibold)).foregroundStyle(accent)
                }
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .preferredColorScheme(.dark)
        .task { await loadAll() }
        .fullScreenCover(item: $opening, onDismiss: { Task { await loadAll() } }) { roll in
            SharedRollView(rollID: roll.id, camera: camera, accent: accent)
        }
        .fullScreenCover(item: $person) { user in
            UserProfileView(userID: user.id, camera: camera, accent: accent)
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .feed:
            rolls(feed, empty: "NOTHING YET\nFOLLOW PEOPLE TO SEE THEIR ROLLS HERE")
        case .shared:
            rolls(shared, empty: "NO ROLLS SHARED WITH YOU YET")
        case .requests:
            requestList
        case .find:
            findList
        }
    }

    private func rolls(_ list: [Social.RollTile]?, empty: String) -> some View {
        Group {
            if let list {
                if list.isEmpty {
                    centered(empty)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 16) {
                            ForEach(list) { roll in tile(roll) }
                        }
                        .padding(.bottom, 16)
                    }
                    .refreshable { await loadAll() }
                }
            } else {
                Spacer()
                ProgressView().frame(maxWidth: .infinity)
                Spacer()
            }
        }
    }

    private func tile(_ roll: Social.RollTile) -> some View {
        Button { opening = OpenSocialRoll(id: roll.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Color(white: 0.1)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: roll.cover) { image in image.resizable().scaledToFill() } placeholder: { Color(white: 0.12) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        if let audience = roll.audience.flatMap(Audience.init(rawValue:)), audience != .everyone {
                            Image(systemName: audience.icon)
                                .font(.system(size: 10, weight: .bold))
                                .padding(6)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                                .padding(6)
                                .accessibilityLabel(audience.label)
                        }
                    }
                Text(roll.title.uppercased()).font(.mono(11, .bold)).foregroundStyle(.white).lineLimit(1)
                if let by = roll.by {
                    HStack(spacing: 6) {
                        PersonAvatar(person: by, size: 16)
                        Text(by.title.uppercased()).font(.mono(9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var requestList: some View {
        if let requests {
            if requests.isEmpty {
                centered("NO FOLLOW REQUESTS")
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(requests) { p in
                            PersonRow(person: p, onOpen: { person = IncomingUser(id: p.id) }) {
                                HStack(spacing: 6) {
                                    SocialChip(text: "APPROVE", selected: true, accent: accent) { answer(p, accept: true) }
                                    SocialChip(text: "DECLINE", accent: accent) { answer(p, accept: false) }
                                }
                            }
                        }
                    }
                }
                Text("Followers see the rolls you share with your followers. You can remove a follower any time from their profile.")
                    .font(.mono(9)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
            }
        } else {
            Spacer()
            ProgressView().frame(maxWidth: .infinity)
            Spacer()
        }
    }

    @ViewBuilder private var findList: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("", text: $query, prompt: Text("@HANDLE OR NAME").foregroundStyle(Color(white: 0.4)))
                .font(.mono(14, .semibold))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Capsule().fill(Color(white: 0.16)))
        .task(id: query) {
            // Search as you type, once you pause.
            let text = query.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
            guard text.count >= 2 else { results = []; return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            do {
                results = try await Social.search(text)
                for p in results { statuses[p.id] = p.status ?? "none" }
            } catch {
                note = error.localizedDescription.uppercased()
            }
        }
        if results.isEmpty {
            centered(query.count >= 2 ? "NOBODY FOUND" : "SEARCH BY @HANDLE OR NAME")
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(results) { p in
                        PersonRow(person: p, onOpen: { person = IncomingUser(id: p.id) }) {
                            FollowButton(id: p.id, status: Binding(get: { statuses[p.id] ?? "none" }, set: { statuses[p.id] = $0 }),
                                         accent: accent, onError: { note = $0 })
                        }
                    }
                }
            }
        }
    }

    private func centered(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).font(.mono(11, .bold)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            Spacer()
        }
    }

    private func answer(_ p: Social.Person, accept: Bool) {
        requests?.removeAll { $0.id == p.id }
        Task {
            do {
                try await Social.answer(p.id, accept: accept)
            } catch {
                note = error.localizedDescription.uppercased()
                await loadAll()
            }
        }
    }

    private func loadAll() async {
        guard account.isSignedIn else { note = "SIGN IN FROM YOUR PROFILE FIRST"; feed = []; shared = []; requests = []; return }
        async let f = try? Social.feed()
        async let s = try? Social.inbox()
        async let r = try? Social.requests()
        let (fv, sv, rv) = await (f, s, r)
        feed = fv ?? []
        shared = sv ?? []
        requests = rv ?? []
    }
}

private struct OpenSocialRoll: Identifiable { let id: String }

// MARK: Followers and following

/// Someone's followers or the people they follow. On your own followers, REMOVE takes
/// someone off.
struct PeopleListSheet: View {
    let userID: String
    let which: String   // "followers" or "following"
    @ObservedObject var camera: CameraModel
    let accent: Color
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var account = Account.shared
    @State private var people: [Social.Person]?
    @State private var note: String?
    @State private var person: IncomingUser?

    private var mine: Bool { account.me?.id == userID }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(which == "followers" ? "FOLLOWERS" : "FOLLOWING").font(.mono(15, .bold)).foregroundStyle(accent)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30).background(Circle().fill(Color(white: 0.16)))
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Close")
            }
            if let note { Text(note).font(.mono(10, .semibold)).foregroundStyle(accent) }
            if let people {
                if people.isEmpty {
                    Spacer()
                    Text(which == "followers" ? "NO FOLLOWERS YET" : "NOT FOLLOWING ANYONE YET")
                        .font(.mono(11, .bold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(people) { p in
                                PersonRow(person: p, onOpen: { person = IncomingUser(id: p.id) }) {
                                    if mine && which == "followers" {
                                        SocialChip(text: "REMOVE", accent: accent) { remove(p) }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                Spacer()
                ProgressView().frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(20)
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .task {
            do { people = try await Social.list(userID, which) } catch { note = error.localizedDescription.uppercased(); people = [] }
        }
        .fullScreenCover(item: $person) { user in
            UserProfileView(userID: user.id, camera: camera, accent: accent)
        }
    }

    private func remove(_ p: Social.Person) {
        people?.removeAll { $0.id == p.id }
        Task {
            do { try await Social.removeFollower(p.id) } catch { note = error.localizedDescription.uppercased() }
        }
    }
}

// MARK: Picking people to share with

/// Choose who a roll is for: your followers and the people you follow, or anyone you find.
struct PeoplePicker: View {
    let accent: Color
    let initial: [String]
    let onDone: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var account = Account.shared
    @State private var known: [Social.Person] = []
    @State private var found: [Social.Person] = []
    @State private var chosen: Set<String> = []
    @State private var query = ""
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SHARE WITH").font(.mono(15, .bold)).foregroundStyle(accent)
                    Text(chosen.isEmpty ? "PICK PEOPLE" : "\(chosen.count) CHOSEN").font(.mono(10)).foregroundStyle(.secondary)
                }
                Spacer()
                SocialChip(text: "DONE", selected: true, accent: accent) {
                    onDone(Array(chosen))
                    dismiss()
                }
                .disabled(chosen.isEmpty)
                .opacity(chosen.isEmpty ? 0.5 : 1)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("", text: $query, prompt: Text("FIND SOMEONE").foregroundStyle(Color(white: 0.4)))
                    .font(.mono(13, .semibold)).foregroundStyle(.white)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Capsule().fill(Color(white: 0.16)))
            .task(id: query) {
                let text = query.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
                guard text.count >= 2 else { found = []; return }
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                found = (try? await Social.search(text)) ?? []
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    let shown = query.count >= 2 ? found : known
                    if shown.isEmpty && !loading {
                        Text(query.count >= 2 ? "NOBODY FOUND" : "YOUR FOLLOWERS AND THE PEOPLE YOU FOLLOW SHOW HERE. SEARCH TO FIND ANYONE ELSE.")
                            .font(.mono(10)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                    ForEach(shown) { p in
                        PersonRow(person: p, onOpen: { toggle(p.id) }) {
                            Image(systemName: chosen.contains(p.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(chosen.contains(p.id) ? accent : Color(white: 0.4))
                                .onTapGesture { toggle(p.id) }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .task {
            chosen = Set(initial)
            guard let me = account.me?.id else { loading = false; return }
            async let followers = try? Social.list(me, "followers")
            async let following = try? Social.list(me, "following")
            let all = ((await followers) ?? []) + ((await following) ?? [])
            var seen = Set<String>()
            known = all.filter { seen.insert($0.id).inserted }
            loading = false
        }
    }

    private func toggle(_ id: String) {
        if chosen.contains(id) { chosen.remove(id) } else { chosen.insert(id) }
    }
}

// MARK: Your handle

/// Your @handle and whether search finds you, on your profile.
struct HandleEditor: View {
    let accent: Color
    @ObservedObject private var account = Account.shared
    @State private var draft = ""
    @State private var note: String?
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HANDLE").font(.mono(9, .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    Text("@").font(.mono(14, .semibold)).foregroundStyle(.secondary)
                    TextField("", text: $draft, prompt: Text("yourname").foregroundStyle(Color(white: 0.4)))
                        .font(.mono(14, .semibold))
                        .foregroundStyle(.white)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(save)
                        .onChange(of: draft) { _, new in
                            let cleaned = String(new.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }.prefix(20))
                            if cleaned != new { draft = cleaned }
                        }
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Capsule().fill(Color(white: 0.16)))
                if draft != (account.me?.handle ?? "") && !draft.isEmpty {
                    SocialChip(text: saving ? "…" : "SAVE", selected: true, accent: accent, action: save)
                }
            }
            if let note {
                Text(note).font(.mono(9, .semibold)).foregroundStyle(accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Text("FIND ME IN SEARCH").font(.mono(9, .semibold)).foregroundStyle(.secondary)
                Spacer()
                SocialChip(text: "ON", selected: account.me?.discoverable != false, accent: accent) { setDiscoverable(true) }
                SocialChip(text: "OFF", selected: account.me?.discoverable == false, accent: accent) { setDiscoverable(false) }
            }
            Text("People find you by your @handle or name, and need one to follow you. Every follow is a request you approve.")
                .font(.mono(9)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { draft = account.me?.handle ?? "" }
        .onChange(of: account.me?.handle) { _, handle in draft = handle ?? draft }
    }

    private func save() {
        guard !draft.isEmpty, draft != account.me?.handle, !saving else { return }
        saving = true
        note = nil
        Task {
            do {
                try await account.updateSocial(handle: draft)
                note = "SAVED"
            } catch {
                note = error.localizedDescription.uppercased()
            }
            saving = false
        }
    }

    private func setDiscoverable(_ on: Bool) {
        Task {
            do { try await account.updateSocial(discoverable: on) } catch { note = error.localizedDescription.uppercased() }
        }
    }
}
