import SwiftUI
import VisionKit


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

    /// The same, in sentence case, for the profile and people screens.
    var title: String {
        switch self {
        case .onlyMe: return "Private"
        case .people: return "Specific people"
        case .followers: return "Followers"
        case .everyone: return "Public"
        case .link: return "Anyone with the link"
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
            return name.isEmpty ? (handle.map { "@\($0)" } ?? "Someone") : name
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

    private struct Browse: Decodable { var people: [Person]; var after: String? }

    /// Everyone findable, by handle, a page at a time: pass the previous page's `after`.
    static func browse(after: String? = nil) async throws -> (people: [Person], after: String?) {
        let data = try await call("api/users/browse", query: after.map { [URLQueryItem(name: "after", value: $0)] } ?? [])
        let page = try JSONDecoder().decode(Browse.self, from: data)
        return (page.people, page.after)
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

    /// Report a person (for example, someone who seems to be under 13); it goes to the admin page.
    static func report(_ id: String, reason: String) async throws {
        _ = try await call("api/users/\(id)/report", method: "POST", json: ["reason": reason])
    }

    private struct RollPage: Decodable { var rolls: [RollTile]; var after: String? }

    /// Everyone's public rolls, newest first, a page at a time: pass the previous page's `after`.
    static func browseRolls(after: String? = nil) async throws -> (rolls: [RollTile], after: String?) {
        let data = try await call("api/rolls/browse", query: after.map { [URLQueryItem(name: "after", value: $0)] } ?? [])
        let page = try JSONDecoder().decode(RollPage.self, from: data)
        return (page.rolls, page.after)
    }

    /// Something a person you follow sent you: a profile or a roll.
    struct Sent: Decodable, Identifiable {
        var key: String
        var kind: String
        var from: Person
        var profile: Person?
        var roll: RollTile?
        var id: String { key }
    }
    private struct Sends: Decodable { var sends: [Sent] }

    /// Send a profile ("profile") or a roll ("roll") to one of your followers, by id or @handle.
    static func send(to: String, kind: String, id: String) async throws {
        _ = try await call("api/sends", method: "POST", json: ["to": to, "kind": kind, "id": id])
    }

    static func sends() async throws -> [Sent] {
        try JSONDecoder().decode(Sends.self, from: try await call("api/me/sends")).sends
    }

    static func dismiss(_ sent: Sent) async throws {
        _ = try await call("api/me/sends/\(sent.key)", method: "DELETE")
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
                        .font(.system(size: size * 0.42, weight: .bold))
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
                    PersonAvatar(person: person, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        if let handle = person.handle {
                            Text("@\(handle)").font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
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
        .padding(.vertical, 9)
    }
}

/// People in a grouped card, one row each, with hairlines between them.
struct PeopleCard<Trailing: View>: View {
    let people: [Social.Person]
    var onOpen: ((Social.Person) -> Void)?
    @ViewBuilder var trailing: (Social.Person) -> Trailing

    var body: some View {
        SettingsCard {
            ForEach(Array(people.enumerated()), id: \.element.id) { index, p in
                PersonRow(person: p, onOpen: onOpen == nil ? nil : { onOpen?(p) }) { trailing(p) }
                    .padding(.horizontal, 14)
                if index < people.count - 1 {
                    CardDivider(inset: 68)
                }
            }
        }
    }
}

/// A small capsule button, in the profile's style: orange with black text when it's the
/// thing to do, grey otherwise.
struct SocialChip: View {
    let text: String
    var selected = false
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SocialChipLabel(text: text, selected: selected, accent: accent)
        }
        .buttonStyle(.plain)
    }
}

/// The look of `SocialChip`, for labels inside a Menu or ShareLink.
struct SocialChipLabel: View {
    let text: String
    var selected = false
    let accent: Color

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(selected ? accent : ProfileStyle.button))
            .foregroundStyle(selected ? .black : .white)
    }
}

/// Follow / Requested / Following for someone, with what tapping it does. `big` makes it a
/// full-width button (on a profile); otherwise it's a small chip (in a list).
struct FollowButton: View {
    let id: String
    @Binding var status: String
    let accent: Color
    var onError: (String) -> Void = { _ in }
    var big = false
    @State private var working = false

    var body: some View {
        Button {
            guard !working else { return }
            working = true
            let on = status == "none"
            Task {
                do {
                    status = try await Social.follow(id, on)
                } catch {
                    onError(error.localizedDescription)
                }
                working = false
            }
        } label: {
            if big {
                PillLabel(text: working ? "…" : label, filled: status == "none", accent: accent)
            } else {
                SocialChipLabel(text: working ? "…" : label, selected: status == "none", accent: accent)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status == "following" ? "Following. Tap to unfollow" : status == "requested" ? "Requested. Tap to cancel" : "Follow")
    }

    private var label: String {
        switch status {
        case "following": return "Following"
        case "requested": return "Requested"
        default: return "Follow"
        }
    }
}

/// The round close button at the top right of the people screens.
struct CloseCircle: View {
    var size: CGFloat = 34
    var fill = Color(white: 0.16)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: size * 0.4, weight: .bold))
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
        }
        .foregroundStyle(.white)
        .accessibilityLabel("Close")
    }
}

/// The search box on the people screens.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var web = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(ProfileStyle.faint))
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(web ? .webSearch : .default)
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color(white: 0.45))
                }
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(ProfileStyle.card))
    }
}

/// An empty list, centred in the space left.
private struct CenteredEmpty: View {
    let icon: String
    let title: String
    var detail: String?

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            EmptyState(icon: icon, title: title, detail: detail)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: The social screen

/// People and the rolls they share with you: your feed, rolls shared with you, follow
/// requests and search. Opened from your profile.
struct SocialView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case feed, browse, shared, requests, find
        var id: String { rawValue }
        var label: String {
            switch self {
            case .feed: return "Following"
            case .browse: return "Browse"
            case .shared: return "Shared with you"
            case .requests: return "Requests"
            case .find: return "Find people"
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
    @State private var sent: [Social.Sent] = []
    @State private var publicRolls: [Social.RollTile]?
    @State private var publicAfter: String?
    @State private var loadingPublic = false
    @State private var everyone: [Social.Person] = []
    @State private var everyoneAfter: String?
    @State private var browsing = false
    @State private var scanning = false
    @State private var showingMyCode = false

    var body: some View {
        ZStack {
            ProfileStyle.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("People").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                    CloseCircle { dismiss() }
                }
                // The tabs scroll edge to edge, so the last one isn't cut off by the margin.
                ScrollView(.horizontal, showsIndicators: false) {
                    ChoicePills(options: Tab.allCases.map { ($0, tabLabel($0)) }, selection: $tab, accent: accent)
                        .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)
                if account.me?.handle == nil {
                    NoteText(text: "Choose a @username in Edit profile so people can find you and you can follow them.", accent: accent)
                }
                if let note {
                    NoteText(text: note, accent: accent)
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
        .fullScreenCover(isPresented: $scanning, onDismiss: { camera.start() }) {
            ProfileScanner(accent: accent) { id in
                scanning = false
                // Open it once the scanner has gone.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { person = IncomingUser(id: id) }
            }
        }
        .sheet(isPresented: $showingMyCode) {
            MyCodeSheet(accent: accent)
        }
    }

    /// A tab's name, with how many are waiting (requests, things sent to you).
    private func tabLabel(_ t: Tab) -> String {
        if t == .requests, let count = requests?.count, count > 0 { return "Requests · \(count)" }
        if t == .shared, !sent.isEmpty { return "Shared with you · \(sent.count)" }
        return t.label
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .feed:
            rolls(feed, empty: CenteredEmpty(icon: "person.2", title: "Nothing here yet",
                                             detail: "Follow people to see the rolls they share."))
        case .browse:
            browseList
        case .shared:
            if !sent.isEmpty {
                VStack(spacing: 8) {
                    ForEach(sent) { item in sentBanner(item) }
                }
            }
            rolls(shared, empty: sent.isEmpty
                  ? CenteredEmpty(icon: "tray", title: "Nothing shared with you yet",
                                  detail: "Rolls people share with you show up here.")
                  : nil)
        case .requests:
            requestList
        case .find:
            findList
        }
    }

    private func rolls(_ list: [Social.RollTile]?, empty: CenteredEmpty?) -> some View {
        Group {
            if let list {
                if list.isEmpty {
                    if let empty { empty } else { Spacer() }
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
                PrintCell(aspect: 4 / 5, cornerRadius: 10) {
                    AsyncImage(url: roll.cover) { image in image.resizable().scaledToFit() } placeholder: { Color(white: 0.12) }
                }
                    .overlay(alignment: .topTrailing) {
                        if let audience = roll.audience.flatMap(Audience.init(rawValue:)), audience != .everyone {
                            Image(systemName: audience.icon)
                                .font(.system(size: 10, weight: .bold))
                                .padding(6)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                                .padding(6)
                                .accessibilityLabel(audience.title)
                        }
                    }
                Text(roll.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if let by = roll.by {
                    HStack(spacing: 6) {
                        PersonAvatar(person: by, size: 18)
                        Text(by.title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// A profile or roll someone sent you, at the top of Shared with you: follow or look,
    /// or dismiss it.
    private func sentBanner(_ item: Social.Sent) -> some View {
        HStack(spacing: 10) {
            if let profile = item.profile {
                PersonAvatar(person: profile, size: 40)
            } else if let roll = item.roll {
                AsyncImage(url: roll.cover) { image in image.resizable().scaledToFill() } placeholder: { Color(white: 0.15) }
                    .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.from.title) sent you").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                Text(item.profile.map { $0.handle.map { "@\($0)" } ?? $0.title } ?? (item.roll?.title ?? ""))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let profile = item.profile {
                if (profile.status ?? "none") == "none" {
                    SocialChip(text: "Follow", selected: true, accent: accent) { acceptFollow(item, profile) }
                }
                SocialChip(text: "View", accent: accent) { person = IncomingUser(id: profile.id) }
            } else if let roll = item.roll {
                SocialChip(text: "View", selected: true, accent: accent) { opening = OpenSocialRoll(id: roll.id) }
            }
            Button { dismissSent(item) } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(white: 0.6))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(ProfileStyle.card))
    }

    /// Accepting a sent profile asks to follow (they still approve), and clears the banner.
    private func acceptFollow(_ item: Social.Sent, _ profile: Social.Person) {
        Task {
            do {
                _ = try await Social.follow(profile.id, true)
                note = "Asked to follow \(profile.title)."
                dismissSent(item)
            } catch {
                note = error.localizedDescription
            }
        }
    }

    private func dismissSent(_ item: Social.Sent) {
        sent.removeAll { $0.key == item.key }
        Task { try? await Social.dismiss(item) }
    }

    /// Everyone's public rolls, newest first. Tap one to look through its frames.
    @ViewBuilder private var browseList: some View {
        if let publicRolls {
            if publicRolls.isEmpty {
                CenteredEmpty(icon: "square.grid.2x2", title: "No public rolls yet",
                              detail: "Rolls people make public show up here.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 16) {
                        ForEach(publicRolls) { roll in tile(roll) }
                    }
                    if loadingPublic {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                    } else if publicAfter != nil {
                        SocialChip(text: "Show more", accent: accent) { Task { await loadPublic(more: true) } }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    } else {
                        Text("That's everything").font(.system(size: 13)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                }
                .refreshable { await loadPublic(more: false) }
            }
        } else {
            Spacer()
            ProgressView().frame(maxWidth: .infinity)
            Spacer()
                .task { await loadPublic(more: false) }
        }
    }

    private func loadPublic(more: Bool) async {
        guard !loadingPublic, account.isSignedIn else { if !account.isSignedIn { publicRolls = [] }; return }
        loadingPublic = true
        defer { loadingPublic = false }
        do {
            let page = try await Social.browseRolls(after: more ? publicAfter : nil)
            publicRolls = more ? (publicRolls ?? []) + page.rolls : page.rolls
            publicAfter = page.after
        } catch {
            note = error.localizedDescription
            if publicRolls == nil { publicRolls = [] }
        }
    }

    @ViewBuilder private var requestList: some View {
        if let requests {
            if requests.isEmpty {
                CenteredEmpty(icon: "person.badge.clock", title: "No follow requests",
                              detail: "When someone asks to follow you, it shows up here.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        PeopleCard(people: requests, onOpen: { p in person = IncomingUser(id: p.id) }) { p in
                            HStack(spacing: 6) {
                                SocialChip(text: "Approve", selected: true, accent: accent) { answer(p, accept: true) }
                                SocialChip(text: "Decline", accent: accent) { answer(p, accept: false) }
                            }
                        }
                        FootnoteText("Followers see the rolls you share with your followers. You can remove a follower any time from their profile.")
                    }
                    .padding(.bottom, 16)
                }
            }
        } else {
            Spacer()
            ProgressView().frame(maxWidth: .infinity)
            Spacer()
        }
    }

    @ViewBuilder private var findList: some View {
        HStack(spacing: 10) {
            PillButton(text: "Scan a code", filled: true, accent: accent) {
                camera.stop()   // the scanner needs the camera
                scanning = true
            }
            PillButton(text: "My code", accent: accent) { showingMyCode = true }
        }
        SearchField(prompt: "@username, name or profile link", text: $query, web: true)
            .task(id: query) {
                // A pasted profile link opens the profile.
                if let id = ProfileScanner.profileID(in: query) {
                    query = ""
                    person = IncomingUser(id: id)
                    return
                }
                // Search as you type, once you pause.
                let text = query.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
                guard text.count >= 2 else { results = []; return }
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                do {
                    results = try await Social.search(text)
                    for p in results { statuses[p.id] = p.status ?? "none" }
                } catch {
                    note = error.localizedDescription
                }
            }
        if query.count >= 2 {
            if results.isEmpty {
                CenteredEmpty(icon: "magnifyingglass", title: "Nobody found",
                              detail: "Try their @username, or paste their profile link.")
            } else {
                ScrollView {
                    peopleCard(results).padding(.bottom, 16)
                }
            }
        } else {
            // Nothing typed: browse everyone who can be found, by handle.
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("Everyone").padding(.top, 4)
                    if !everyone.isEmpty {
                        peopleCard(everyone)
                    }
                    if browsing {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                    } else if everyoneAfter != nil {
                        SocialChip(text: "Show more", accent: accent) { Task { await browse(more: true) } }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    } else if everyone.isEmpty {
                        Text("Nobody to show yet.").font(.system(size: 14)).foregroundStyle(.secondary).padding(.top, 4)
                    }
                    FootnoteText("Only people who chose a @username and left Find me in search on are listed.")
                        .padding(.top, 4).padding(.bottom, 16)
                }
            }
            .task { if everyone.isEmpty { await browse(more: false) } }
        }
    }

    /// People with a Follow button each.
    private func peopleCard(_ list: [Social.Person]) -> some View {
        PeopleCard(people: list, onOpen: { p in person = IncomingUser(id: p.id) }) { p in
            FollowButton(id: p.id, status: Binding(get: { statuses[p.id] ?? p.status ?? "none" }, set: { statuses[p.id] = $0 }),
                         accent: accent, onError: { note = $0 })
        }
    }

    private func browse(more: Bool) async {
        guard !browsing, account.isSignedIn else { return }
        browsing = true
        defer { browsing = false }
        do {
            let page = try await Social.browse(after: more ? everyoneAfter : nil)
            everyone = more ? everyone + page.people : page.people
            everyoneAfter = page.after
        } catch {
            note = error.localizedDescription
        }
    }

    private func answer(_ p: Social.Person, accept: Bool) {
        requests?.removeAll { $0.id == p.id }
        Task {
            do {
                try await Social.answer(p.id, accept: accept)
            } catch {
                note = error.localizedDescription
                await loadAll()
            }
        }
    }

    private func loadAll() async {
        guard account.isSignedIn else { note = "Sign in from your profile first."; feed = []; shared = []; requests = []; return }
        async let f = try? Social.feed()
        async let s = try? Social.inbox()
        async let r = try? Social.requests()
        async let n = try? Social.sends()
        let (fv, sv, rv, nv) = await (f, s, r, n)
        feed = fv ?? []
        shared = sv ?? []
        requests = rv ?? []
        sent = nv ?? []
    }
}

private struct OpenSocialRoll: Identifiable { let id: String }

// MARK: Followers and following

/// Someone's followers or the people they follow. On your own followers, Remove takes
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(which == "followers" ? "Followers" : "Following").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                Spacer()
                CloseCircle(size: 30) { dismiss() }
            }
            if let note { NoteText(text: note, accent: accent) }
            if let people {
                if people.isEmpty {
                    CenteredEmpty(icon: "person.2",
                                  title: which == "followers" ? "No followers yet" : "Not following anyone yet",
                                  detail: which == "followers" ? "People who follow \(mine ? "you" : "them") show up here."
                                                                : "People \(mine ? "you follow" : "they follow") show up here.")
                } else {
                    ScrollView {
                        PeopleCard(people: people, onOpen: { p in person = IncomingUser(id: p.id) }) { p in
                            if mine && which == "followers" {
                                SocialChip(text: "Remove", accent: accent) { remove(p) }
                            }
                        }
                        .padding(.bottom, 16)
                    }
                }
            } else {
                Spacer()
                ProgressView().frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(20)
        .background(ProfileStyle.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .task {
            do { people = try await Social.list(userID, which) } catch { note = error.localizedDescription; people = [] }
        }
        .fullScreenCover(item: $person) { user in
            UserProfileView(userID: user.id, camera: camera, accent: accent)
        }
    }

    private func remove(_ p: Social.Person) {
        people?.removeAll { $0.id == p.id }
        Task {
            do { try await Social.removeFollower(p.id) } catch { note = error.localizedDescription }
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Share with").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    Text(chosen.isEmpty ? "Pick people" : "\(chosen.count) chosen").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                SocialChip(text: "Done", selected: true, accent: accent) {
                    onDone(Array(chosen))
                    dismiss()
                }
                .disabled(chosen.isEmpty)
                .opacity(chosen.isEmpty ? 0.5 : 1)
            }
            SearchField(prompt: "Find someone", text: $query)
                .task(id: query) {
                    let text = query.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
                    guard text.count >= 2 else { found = []; return }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    found = (try? await Social.search(text)) ?? []
                }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let shown = query.count >= 2 ? found : known
                    if shown.isEmpty && !loading {
                        FootnoteText(query.count >= 2 ? "Nobody found." : "Your followers and the people you follow show here. Search to find anyone else.")
                            .padding(.top, 4)
                    }
                    if !shown.isEmpty {
                        PeopleCard(people: shown, onOpen: { p in toggle(p.id) }) { p in
                            Image(systemName: chosen.contains(p.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(chosen.contains(p.id) ? accent : Color(white: 0.4))
                                .onTapGesture { toggle(p.id) }
                                .accessibilityLabel(chosen.contains(p.id) ? "Chosen" : "Not chosen")
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .padding(20)
        .background(ProfileStyle.background.ignoresSafeArea())
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

// MARK: Codes

/// Scan someone's profile code (or any Film Exposures profile link) with the camera.
struct ProfileScanner: View {
    let accent: Color
    let onFound: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    /// A profile from a scanned or pasted link: an id (https://filmexposures.com/u/<id> or
    /// exposures://u/<id>) or "@handle" (https://filmexposures.com/@handle), which the
    /// profile view looks up.
    static func profileID(in text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.contains("/u/") || value.contains("/@") else { return nil }
        if !value.contains("://") { value = "https://" + value }
        guard let url = URL(string: value) else { return nil }
        return ShareLinks.userID(from: url) ?? ShareLinks.userHandle(from: url)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                CodeScanner { payload in
                    if let id = Self.profileID(in: payload) { onFound(id) }
                }
                .ignoresSafeArea()
                RoundedRectangle(cornerRadius: 22)
                    .stroke(accent, lineWidth: 2)
                    .frame(width: 240, height: 240)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            } else {
                Text("This iPhone can't scan codes here.\nPoint the Camera app at the code instead: it opens the profile in Film Exposures.")
                    .font(.system(size: 15)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Text("Scan a profile code").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                CloseCircle(fill: Color.black.opacity(0.6)) { dismiss() }
            }
            .padding(16)
        }
        .preferredColorScheme(.dark)
    }
}

/// VisionKit's live scanner, for QR codes only.
private struct CodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                if case .barcode(let code) = item, let payload = code.payloadStringValue,
                   ProfileScanner.profileID(in: payload) != nil {
                    done = true
                    onCode(payload)
                    return
                }
            }
        }
    }
}

/// Your profile as a QR code, for someone to scan in person.
struct MyCodeSheet: View {
    let accent: Color
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var account = Account.shared

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("My code").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                Spacer()
                CloseCircle(size: 30) { dismiss() }
            }
            if let me = account.me, let image = Self.code(for: me.url) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
                    .frame(maxWidth: 260)
                    .accessibilityLabel("Your profile code")
                if let handle = me.handle {
                    Text("@\(handle)").font(.system(size: 18, weight: .semibold)).foregroundStyle(accent)
                }
                Text("Someone scans this in Find people, or with the Camera app, to open your profile and ask to follow.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                ShareLink(item: me.url) {
                    PillLabel(text: "Share profile link", filled: true, accent: accent, fullWidth: false)
                }
                .buttonStyle(.plain)
            } else {
                EmptyState(icon: "person.crop.circle", title: "Sign in from your profile first")
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(ProfileStyle.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    /// A crisp QR code for a link (Core Image, scaled up without smoothing).
    static func code(for url: URL) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(url.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: Send in Film Exposures

/// The app's own button in the share sheet: send a profile or a roll to one of your
/// followers, who finds it at the top of SHARED WITH YOU.
final class SendInAppActivity: UIActivity {
    private let kind: String
    private let itemID: String

    init(kind: String, id: String) {
        self.kind = kind
        self.itemID = id
        super.init()
    }

    /// The button for a profile or a roll, when you're signed in (else none).
    @MainActor static func forProfile(_ id: String) -> [UIActivity] {
        Account.shared.isSignedIn ? [SendInAppActivity(kind: "profile", id: id)] : []
    }

    @MainActor static func forRoll(_ id: String) -> [UIActivity] {
        Account.shared.isSignedIn ? [SendInAppActivity(kind: "roll", id: id)] : []
    }

    override class var activityCategory: UIActivity.Category { .share }
    override var activityType: UIActivity.ActivityType? { UIActivity.ActivityType("com.davidanderson.retrocam.send") }
    override var activityTitle: String? { "Send in Film Exposures" }
    /// The app's icon (a copy at share-sheet size, drawn as is), so the button in the share
    /// sheet's row of apps looks like Film Exposures. It sits at the end of that row.
    override var activityImage: UIImage? { UIImage(named: "ShareIcon")?.withRenderingMode(.alwaysOriginal) ?? UIImage(systemName: "paperplane") }
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool { true }

    override var activityViewController: UIViewController? {
        let finish = ShutterFinish(rawValue: UserDefaults.standard.string(forKey: ShutterFinish.storageKey) ?? "") ?? .copper
        let sheet = SendSheet(kind: kind, id: itemID, accent: finish.palette.accent) { [weak self] sent in
            self?.activityDidFinish(sent)
        }
        let host = UIHostingController(rootView: sheet)
        host.overrideUserInterfaceStyle = .dark
        return host
    }
}

/// Pick one of your followers to send a profile or roll to.
struct SendSheet: View {
    let kind: String
    let id: String
    let accent: Color
    let onDone: (Bool) -> Void
    @ObservedObject private var account = Account.shared
    @State private var followers: [Social.Person]?
    @State private var query = ""
    @State private var sending: String?
    @State private var note: String?

    private var shown: [Social.Person] {
        let q = query.lowercased().replacingOccurrences(of: "@", with: "")
        guard !q.isEmpty else { return followers ?? [] }
        return (followers ?? []).filter { ($0.handle ?? "").contains(q) || ($0.name ?? "").lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind == "roll" ? "Send this roll" : "Send this profile").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    Text("To one of your followers").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                CloseCircle(size: 30) { onDone(false) }
            }
            SearchField(prompt: "@username or name", text: $query)
            if let note {
                NoteText(text: note, accent: accent)
            }
            if let followers {
                if followers.isEmpty {
                    CenteredEmpty(icon: "person.2", title: "Nobody follows you yet",
                                  detail: "You can send things to your followers.")
                } else {
                    ScrollView {
                        PeopleCard(people: shown, onOpen: { p in send(to: p) }) { p in
                            SocialChip(text: sending == p.id ? "…" : "Send", selected: true, accent: accent) { send(to: p) }
                        }
                        .padding(.bottom, 16)
                    }
                }
            } else {
                Spacer()
                ProgressView().frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(20)
        .background(ProfileStyle.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            guard let me = account.me?.id else { followers = []; return }
            followers = (try? await Social.list(me, "followers")) ?? []
        }
    }

    private func send(to person: Social.Person) {
        guard sending == nil else { return }
        sending = person.id
        note = nil
        Task {
            do {
                try await Social.send(to: person.id, kind: kind, id: id)
                note = "Sent to \(person.title)."
                try? await Task.sleep(nanoseconds: 700_000_000)
                onDone(true)
            } catch {
                note = error.localizedDescription
            }
            sending = nil
        }
    }
}
