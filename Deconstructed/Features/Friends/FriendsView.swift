import SwiftUI

struct FriendsView: View {
    @Environment(AppModel.self) private var model

    private enum Pane: String, CaseIterable, Identifiable {
        case feed = "Feed"
        case people = "People"
        var id: String { rawValue }
    }

    @State private var pane: Pane = .feed
    @State private var feed: [FeedItem]?
    @State private var feedError: String?
    @State private var following: [UserProfile] = []
    @State private var followers: [UserProfile] = []
    @State private var query = ""
    @State private var searchResults: [UserProfile] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    Picker("Section", selection: $pane) {
                        ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch pane {
                    case .feed: feedPane
                    case .people: peoplePane
                    }
                }
                .padding(Theme.spacing)
            }
            .screenBackground()
            .navigationTitle("Friends")
            .appRoutes()
            .refreshable { await reload() }
            .task { await reload() }
        }
    }

    // MARK: Feed

    @ViewBuilder
    private var feedPane: some View {
        if let feed {
            if feed.isEmpty {
                EmptyState(symbol: "person.2", title: "Your feed is quiet",
                           message: "Follow people to see the visits they've chosen to share, with the full breakdown behind each score.",
                           actionTitle: "Find people") { pane = .people }
                    .card()
            } else {
                ForEach(feed) { item in
                    NavigationLink(value: Route.visit(item.visit, author: item.author)) {
                        FeedCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
                Text("You only see reviews their authors have made public or shared with followers.")
                    .font(.caption).foregroundStyle(Theme.inkSoft)
            }
        } else if let feedError {
            ErrorBanner(message: feedError) { Task { await reload() } }
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
        }
    }

    // MARK: People

    private var peoplePane: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkSoft).accessibilityHidden(true)
                TextField("Find people by name or username", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                if isSearching { ProgressView() }
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .environment(\.colorScheme, .light)
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline) }

            if !query.isBlank {
                SectionTitle("Results")
                if searchResults.isEmpty, !isSearching {
                    Text("No one found. Search needs at least two characters.")
                        .font(.subheadline).foregroundStyle(Theme.inkSoft).card()
                }
                ForEach(searchResults) { personRow($0) }
            }

            SectionTitle("Following", detail: following.isEmpty ? "No one yet" : "\(following.count)")
            ForEach(following) { personRow($0) }

            SectionTitle("Followers", detail: followers.isEmpty
                ? "No one yet"
                : "\(followers.count) · they can read your followers-only reviews")
            ForEach(followers) { follower in
                HStack {
                    NavigationLink(value: Route.user(follower)) { PersonLabel(profile: follower) }.buttonStyle(.plain)
                    Spacer()
                    AsyncButton("Remove") {
                        try await model.removeFollower(follower)
                        followers.removeAll { $0.id == follower.id }
                    }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityLabel("Remove \(follower.displayName) as a follower")
                }
                .card(padding: 12)
            }
        }
        .onChange(of: query) { _, newValue in
            if newValue.isBlank { searchResults = [] }
        }
    }

    private func personRow(_ person: UserProfile) -> some View {
        HStack {
            NavigationLink(value: Route.user(person)) { PersonLabel(profile: person) }.buttonStyle(.plain)
            Spacer()
            FollowButton(user: person, isFollowing: following.contains { $0.id == person.id }) { nowFollowing in
                following.removeAll { $0.id == person.id }
                if nowFollowing { following.append(person) }
                Task { await loadFeed() }
            }
        }
        .card(padding: 12)
    }

    // MARK: Loading

    private func reload() async {
        await loadFeed()
        following = (try? await model.loadFollowing()) ?? following
        followers = (try? await model.loadFollowers()) ?? followers
    }

    private func loadFeed() async {
        do {
            feed = try await model.loadFeed()
            feedError = nil
        } catch {
            if feed == nil { feedError = error.localizedDescription }
        }
    }

    private func search() async {
        isSearching = true
        defer { isSearching = false }
        do {
            searchResults = try await model.searchUsers(query)
        } catch {
            model.toast = error.localizedDescription
        }
    }
}

struct PersonLabel: View {
    var profile: UserProfile

    var body: some View {
        HStack(spacing: 10) {
            Avatar(profile: profile)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text("@\(profile.username)").font(.caption).foregroundStyle(Theme.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct FollowButton: View {
    @Environment(AppModel.self) private var model
    var user: UserProfile
    var isFollowing: Bool
    var onChange: (Bool) -> Void

    var body: some View {
        AsyncButton {
            try await model.setFollowing(user, following: !isFollowing)
            onChange(!isFollowing)
        } label: {
            Text(isFollowing ? "Following" : "Follow")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isFollowing ? Theme.ink : Theme.alabaster)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isFollowing ? Theme.fill : Theme.rose, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFollowing ? "Following \(user.displayName). Tap to unfollow." : "Follow \(user.displayName)")
    }
}

/// A friend's completed visit with the rubric breakdown behind the number.
struct FeedCard: View {
    @Environment(AppModel.self) private var model
    var item: FeedItem

    var body: some View {
        let place = model.place(for: item.visit.restaurantID)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Avatar(profile: item.author, size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.author.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(item.visit.visitedOn.visitFormatted).font(.caption).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                if item.visit.visibility == .followers {
                    Tag(text: "Followers", symbol: "person.2")
                }
            }
            HStack(spacing: 8) {
                Text(model.displayName(for: item.visit.restaurantID))
                    .font(.display(.title3))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                if place?.isDemo == true { DemoBadge() }
            }
            if let revision = item.visit.activeRevision {
                RatingSummary(revision: revision, showsDescriptions: false)
            }
            if !item.visit.notes.isEmpty {
                Text(item.visit.notes).font(.subheadline).foregroundStyle(Theme.inkSoft).lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .card()
        .overlay(alignment: .top) {
            Capsule().fill(Theme.spectrum).frame(height: 4).padding(.horizontal, 28)
        }
        .task(id: model.placeReloadToken) { await model.ensurePlace(for: item.visit.restaurantID) }
    }
}

/// Another person's profile: only the visits they've allowed you to read.
struct UserProfileView: View {
    @Environment(AppModel.self) private var model
    var user: UserProfile

    @State private var visits: [Visit]?
    @State private var isFollowing = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                HStack(spacing: 14) {
                    Avatar(profile: user, size: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName).font(.display(.title2, weight: .bold)).foregroundStyle(Theme.ink)
                        Text("@\(user.username)").font(.subheadline).foregroundStyle(Theme.inkSoft)
                        if model.isDemo { DemoBadge() }
                    }
                    Spacer()
                    FollowButton(user: user, isFollowing: isFollowing) { nowFollowing in
                        isFollowing = nowFollowing
                        Task { await load() }
                    }
                }

                SectionTitle("Reviews", detail: isFollowing ? "Public and followers-only reviews" : "Public reviews. Follow to see followers-only ones.")
                if let visits {
                    if visits.isEmpty {
                        Text("Nothing shared with you yet.").font(.subheadline).foregroundStyle(Theme.inkSoft).card()
                    }
                    ForEach(visits) { visit in
                        NavigationLink(value: Route.visit(visit, author: user)) {
                            FeedCard(item: FeedItem(visit: visit, author: user))
                        }
                        .buttonStyle(.plain)
                    }
                } else if let errorMessage {
                    ErrorBanner(message: errorMessage) { Task { await load() } }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                }
            }
            .padding(Theme.spacing)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            isFollowing = try await model.loadFollowing().contains { $0.id == user.id }
            visits = try await model.loadVisits(of: user)
            errorMessage = nil
        } catch {
            if visits == nil { errorMessage = error.localizedDescription }
        }
    }
}
