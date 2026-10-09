import Foundation

/// An in-memory stand-in for Supabase. It applies the same rules as the database functions
/// and row-level security in `supabase/migrations`, so the demo behaves like the real thing
/// and the unit tests can exercise those rules without a server.
@MainActor
final class DemoBackend: BackendService {
    let isDemo = true

    private(set) var state: DemoState
    private var photoBytes: [String: Data] = [:]
    private let storeURL: URL?
    private let controls: DemoControls?

    /// - Parameter persist: keep demo edits between launches. Tests pass `false`.
    init(persist: Bool = true, controls: DemoControls? = nil, seed: DemoState? = nil) {
        self.controls = controls
        storeURL = persist ? Self.defaultStoreURL : nil
        if let seed {
            state = seed
        } else if let storeURL, let data = try? Data(contentsOf: storeURL),
                  let saved = try? JSONDecoder().decode(DemoState.self, from: data),
                  saved.schema == DemoState.currentSchema {
            state = saved
        } else {
            state = DemoSeed.make()
        }
    }

    func resetToSeed() {
        let signedIn = state.signedInUserID
        state = DemoSeed.make()
        state.signedInUserID = signedIn
        photoBytes = [:]
        persist()
    }

    /// Switches which demo person is signed in. Used by tests to check what others can see.
    func impersonate(_ userID: UUID) {
        state.signedInUserID = userID
    }

    // MARK: Session

    func restoreSession() async throws -> UserProfile? {
        state.signedInUserID.flatMap(user)
    }

    func signInWithApple(idToken: String, nonce: String, displayName: String?) async throws -> UserProfile {
        throw BackendError.notAllowed("Sign in with Apple needs Supabase credentials. This build is running the demo.")
    }

    func signInDemo() async throws -> UserProfile {
        if user(DemoSeed.meID) == nil {
            state.users.append(UserProfile(id: DemoSeed.meID, username: "you", displayName: "You",
                                           defaultSystemID: StarterSystems.general))
        }
        state.signedInUserID = DemoSeed.meID
        persist()
        return try me()
    }

    func signOut() async throws {
        state.signedInUserID = nil
        persist()
    }

    func deleteAccount() async throws {
        let id = try me().id
        let ownedSystems = Set(state.systems.filter { $0.ownerID == id }.map(\.id))
        state.visits.removeAll { $0.userID == id }
        state.saved[id] = nil
        state.follows.removeAll { $0.followerID == id || $0.followeeID == id }
        state.versions.removeAll { ownedSystems.contains($0.systemID) }
        state.systems.removeAll { ownedSystems.contains($0.id) }
        state.users.removeAll { $0.id == id }
        state.signedInUserID = nil
        persist()
    }

    func updateProfile(_ profile: UserProfile) async throws -> UserProfile {
        let id = try me().id
        guard profile.id == id, let index = state.users.firstIndex(where: { $0.id == id }) else {
            throw BackendError.notAllowed("You can only change your own profile.")
        }
        let username = profile.username.trimmed.lowercased()
        guard username.count >= 3 else { throw BackendError.invalid("Usernames need at least 3 characters.") }
        guard !state.users.contains(where: { $0.id != id && $0.username == username }) else {
            throw BackendError.invalid("That username is taken.")
        }
        var updated = profile
        updated.username = username
        updated.displayName = profile.displayName.trimmed.isEmpty ? username : profile.displayName.trimmed
        state.users[index] = updated
        persist()
        return updated
    }

    // MARK: Ranking systems

    func loadCatalog() async throws -> SystemCatalog {
        let id = try me().id
        let systems = state.systems.filter { $0.ownerID == nil || $0.ownerID == id }
        let ids = Set(systems.map(\.id))
        return SystemCatalog(systems: systems, versions: state.versions.filter { ids.contains($0.systemID) })
    }

    func loadDefinitions(versionIDs: [UUID]) async throws -> SystemCatalog {
        let viewer = try me().id
        let wanted = Set(versionIDs)
        // A definition is readable when it is standard, yours, or behind a rating you can read.
        let readableThroughVisits = Set(state.visits.filter { canView($0, viewer: viewer) }
            .compactMap(\.activeRevision?.versionID))
        let versions = state.versions.filter { version in
            guard wanted.contains(version.id), let system = system(version.systemID) else { return false }
            return system.ownerID == nil || system.ownerID == viewer || readableThroughVisits.contains(version.id)
        }
        let systemIDs = Set(versions.map(\.systemID))
        var systems = state.systems.filter { systemIDs.contains($0.id) }
        for index in systems.indices where systems[index].ownerID != viewer { systems[index].draft = nil }
        return SystemCatalog(systems: systems, versions: versions)
    }

    func saveDraft(systemID: UUID?, draft: SystemDraft, forkedFrom: UUID?) async throws -> RankingSystem {
        try gate()
        let owner = try me().id
        let now = Date.now
        if let systemID {
            let index = try ownedSystemIndex(systemID, owner: owner)
            state.systems[index].draft = draft
            if state.systems[index].isDraftOnly {
                state.systems[index].name = draft.name.trimmed.isEmpty ? "Untitled system" : draft.name.trimmed
                state.systems[index].summary = draft.summary.trimmed
            }
            state.systems[index].updatedAt = now
            persist()
            return state.systems[index]
        }
        let source = forkedFrom.flatMap(system)
        let created = RankingSystem(
            id: UUID(), ownerID: owner, templateKey: source?.templateKey, forkedFromSystemID: source?.id,
            name: draft.name.trimmed.isEmpty ? "Untitled system" : draft.name.trimmed,
            summary: draft.summary.trimmed, currentVersionID: nil, draft: draft, createdAt: now, updatedAt: now)
        state.systems.append(created)
        persist()
        return created
    }

    func publish(systemID: UUID, draft: SystemDraft) async throws -> SystemCatalog {
        try gate()
        let owner = try me().id
        let index = try ownedSystemIndex(systemID, owner: owner)
        guard !state.systems[index].isArchived else {
            throw BackendError.notAllowed("Restore this system from the archive before changing it.")
        }
        if let issue = SystemValidator.issues(for: draft).first {
            throw BackendError.invalid(issue.message)
        }
        let existing = state.versions.filter { $0.systemID == systemID }
        let current = existing.first { $0.id == state.systems[index].currentVersionID }
        if SystemValidator.requiresNewVersion(draft, comparedTo: current) {
            let version = SystemVersion(
                id: UUID(), systemID: systemID, number: (existing.map(\.number).max() ?? 0) + 1,
                criteria: SystemValidator.newVersionCriteria(from: draft), publishedAt: .now)
            state.versions.append(version)
            state.systems[index].currentVersionID = version.id
        }
        state.systems[index].name = draft.name.trimmed
        state.systems[index].summary = draft.summary.trimmed
        state.systems[index].draft = nil
        state.systems[index].updatedAt = .now
        persist()
        return SystemCatalog(systems: [state.systems[index]], versions: state.versions.filter { $0.systemID == systemID })
    }

    func setArchived(systemID: UUID, archived: Bool) async throws -> RankingSystem {
        try gate()
        let index = try ownedSystemIndex(systemID, owner: try me().id)
        state.systems[index].isArchived = archived
        state.systems[index].updatedAt = .now
        persist()
        return state.systems[index]
    }

    func deleteSystem(systemID: UUID) async throws {
        try gate()
        let index = try ownedSystemIndex(systemID, owner: try me().id)
        let inUse = state.visits.contains { $0.revisions.contains { $0.systemID == systemID } }
        guard !inUse else {
            throw BackendError.notAllowed("This system has ratings, so it can't be deleted. Archive it instead to keep those ratings readable.")
        }
        state.versions.removeAll { $0.systemID == systemID }
        state.systems.remove(at: index)
        persist()
    }

    // MARK: Restaurants and saved places

    func ensureRestaurant(provider: String, placeID: String, coordinate: Coordinate?) async throws -> RestaurantRef {
        try gate()
        _ = try me()
        if let index = state.restaurants.firstIndex(where: { $0.provider == provider && $0.providerPlaceID == placeID }) {
            if let coordinate {
                state.restaurants[index].cachedCoordinate = coordinate
                state.restaurants[index].coordinateCachedAt = .now
                persist()
            }
            return state.restaurants[index]
        }
        let ref = RestaurantRef(id: UUID(), provider: provider, providerPlaceID: placeID,
                                cachedCoordinate: coordinate, coordinateCachedAt: coordinate == nil ? nil : .now)
        state.restaurants.append(ref)
        persist()
        return ref
    }

    func loadRestaurants(ids: [UUID]) async throws -> [RestaurantRef] {
        let wanted = Set(ids)
        return state.restaurants.filter { wanted.contains($0.id) }
    }

    func cacheCoordinate(restaurantID: UUID, coordinate: Coordinate) async throws -> RestaurantRef {
        guard let index = state.restaurants.firstIndex(where: { $0.id == restaurantID }) else { throw BackendError.notFound }
        state.restaurants[index].cachedCoordinate = coordinate
        state.restaurants[index].coordinateCachedAt = .now
        persist()
        return state.restaurants[index]
    }

    func loadSaved() async throws -> [SavedPlace] {
        state.saved[try me().id] ?? []
    }

    func setSaved(restaurantID: UUID, saved: Bool) async throws {
        try gate()
        let id = try me().id
        var list = state.saved[id] ?? []
        list.removeAll { $0.restaurantID == restaurantID }
        if saved { list.append(SavedPlace(restaurantID: restaurantID, savedAt: .now)) }
        state.saved[id] = list
        persist()
    }

    // MARK: Visits and ratings

    func loadMyVisits() async throws -> [Visit] {
        let id = try me().id
        return state.visits.filter { $0.userID == id }
    }

    func createVisit(restaurantID: UUID, details: VisitDetails) async throws -> Visit {
        try gate()
        let id = try me().id
        guard state.restaurants.contains(where: { $0.id == restaurantID }) else { throw BackendError.notFound }
        var visit = Visit(id: UUID(), userID: id, restaurantID: restaurantID, visitedOn: details.visitedOn,
                          visibility: details.visibility, createdAt: .now, updatedAt: .now)
        try apply(details, to: &visit)
        state.visits.append(visit)
        persist()
        return visit
    }

    func updateVisit(id: UUID, details: VisitDetails) async throws -> Visit {
        try gate()
        let index = try ownedVisitIndex(id)
        try apply(details, to: &state.visits[index])
        state.visits[index].updatedAt = .now
        persist()
        return state.visits[index]
    }

    func deleteVisit(id: UUID) async throws {
        try gate()
        let index = try ownedVisitIndex(id)
        for photo in state.visits[index].photos { photoBytes[photo.storagePath] = nil }
        state.visits.remove(at: index)
        persist()
    }

    func saveRating(visitID: UUID, versionID: UUID, scores: [UUID: Int], complete: Bool) async throws -> Visit {
        try gate()
        let profile = try me()
        let index = try ownedVisitIndex(visitID)
        guard let version = state.versions.first(where: { $0.id == versionID }),
              let system = system(version.systemID) else { throw BackendError.notFound }
        guard system.ownerID == nil || system.ownerID == profile.id else {
            throw BackendError.notAllowed("You can only rate with the standard systems or your own.")
        }

        let visit = state.visits[index]
        // Continuing with the version a rating already uses is always allowed. Anything else
        // is a fresh choice and must be a current, unarchived system.
        let continuing = visit.activeRevision?.versionID == versionID || visit.draftRevision?.versionID == versionID
        if !continuing {
            let archived = system.isArchived || profile.archivedStandardSystemIDs.contains(system.id)
            guard !archived else {
                throw BackendError.notAllowed("“\(system.name)” is archived and can't be used for new ratings.")
            }
            guard system.currentVersionID == versionID else {
                throw BackendError.notAllowed("New ratings use the latest version of “\(system.name)”.")
            }
        }

        let issues = RatingEngine.issues(scores: scores, version: version, requireComplete: complete)
        if let issue = issues.first { throw BackendError.invalid(issue.message) }

        var revisions = visit.revisions.filter { $0.state != .draft }
        if complete {
            let unchanged = visit.activeRevision.map { $0.versionID == versionID && $0.scores == scores } ?? false
            if !unchanged {
                for i in revisions.indices where revisions[i].state == .active { revisions[i].state = .superseded }
                revisions.append(RatingRevision(
                    id: UUID(), visitID: visitID, systemID: system.id, versionID: versionID, scores: scores,
                    state: .active, createdAt: .now, completedAt: .now,
                    // The total is derived here, never accepted from the caller.
                    total: RatingEngine.completedTotal(scores: scores, version: version)))
            }
        } else {
            revisions.append(RatingRevision(
                id: visit.draftRevision?.id ?? UUID(), visitID: visitID, systemID: system.id, versionID: versionID,
                scores: scores, state: .draft, createdAt: visit.draftRevision?.createdAt ?? .now))
        }
        state.visits[index].revisions = revisions
        state.visits[index].updatedAt = .now
        persist()
        return state.visits[index]
    }

    func discardDraftRating(visitID: UUID) async throws -> Visit {
        try gate()
        let index = try ownedVisitIndex(visitID)
        state.visits[index].revisions.removeAll { $0.state == .draft }
        persist()
        return state.visits[index]
    }

    func addPhoto(visitID: UUID, jpeg: Data) async throws -> Visit {
        try gate()
        let index = try ownedVisitIndex(visitID)
        let photo = VisitPhoto(id: UUID(), storagePath: "\(state.visits[index].userID.uuidString)/\(visitID.uuidString)/\(UUID().uuidString).jpg")
        photoBytes[photo.storagePath] = jpeg
        if let url = photoURL(photo) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? jpeg.write(to: url)
        }
        state.visits[index].photos.append(photo)
        persist()
        return state.visits[index]
    }

    func removePhoto(visitID: UUID, photoID: UUID) async throws -> Visit {
        try gate()
        let index = try ownedVisitIndex(visitID)
        for photo in state.visits[index].photos where photo.id == photoID {
            photoBytes[photo.storagePath] = nil
            if let url = photoURL(photo) { try? FileManager.default.removeItem(at: url) }
        }
        state.visits[index].photos.removeAll { $0.id == photoID }
        persist()
        return state.visits[index]
    }

    func photoData(_ photo: VisitPhoto) async throws -> Data {
        if let data = photoBytes[photo.storagePath] { return data }
        if let url = photoURL(photo), let data = try? Data(contentsOf: url) { return data }
        throw BackendError.notFound
    }

    // MARK: Friends and community

    func searchUsers(_ query: String) async throws -> [UserProfile] {
        try gate()
        let id = try me().id
        let needle = query.trimmed.lowercased()
        guard needle.count >= 2 else { return [] }
        return state.users.filter {
            $0.id != id && ($0.username.contains(needle) || $0.displayName.lowercased().contains(needle))
        }
    }

    func loadFollowing() async throws -> [UserProfile] {
        let id = try me().id
        return state.follows.filter { $0.followerID == id }.compactMap { user($0.followeeID) }
    }

    func loadFollowers() async throws -> [UserProfile] {
        let id = try me().id
        return state.follows.filter { $0.followeeID == id }.compactMap { user($0.followerID) }
    }

    func setFollowing(userID: UUID, following: Bool) async throws {
        try gate()
        let id = try me().id
        guard userID != id else { throw BackendError.invalid("You can't follow yourself.") }
        state.follows.removeAll { $0.followerID == id && $0.followeeID == userID }
        if following { state.follows.append(DemoFollow(followerID: id, followeeID: userID)) }
        persist()
    }

    func removeFollower(userID: UUID) async throws {
        try gate()
        let id = try me().id
        state.follows.removeAll { $0.followerID == userID && $0.followeeID == id }
        persist()
    }

    func loadFeed() async throws -> [FeedItem] {
        try gate()
        let id = try me().id
        let following = Set(state.follows.filter { $0.followerID == id }.map(\.followeeID))
        return state.visits
            .filter { following.contains($0.userID) && $0.isCompleted && canView($0, viewer: id) }
            .sorted { RankingEngine.isLater($0, than: $1) }
            .prefix(60)
            .compactMap { visit in user(visit.userID).map { FeedItem(visit: visit, author: $0) } }
    }

    func loadVisits(ofUser userID: UUID) async throws -> [Visit] {
        try gate()
        let id = try me().id
        return state.visits
            .filter { $0.userID == userID && $0.isCompleted && canView($0, viewer: id) }
            .sorted { RankingEngine.isLater($0, than: $1) }
    }

    func communityScores(provider: String, placeID: String) async throws -> [CommunityScore] {
        try gate()
        guard let restaurant = state.restaurants.first(where: { $0.provider == provider && $0.providerPlaceID == placeID }) else {
            return []
        }
        return CommunityAggregator.scores(
            restaurantID: restaurant.id, visits: state.visits,
            systems: Dictionary(uniqueKeysWithValues: state.systems.map { ($0.id, $0) }),
            versions: Dictionary(uniqueKeysWithValues: state.versions.map { ($0.id, $0) }))
    }

    // MARK: Internals

    private static var defaultStoreURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Demo", isDirectory: true).appendingPathComponent("state.json")
    }

    private func photoURL(_ photo: VisitPhoto) -> URL? {
        storeURL?.deletingLastPathComponent().appendingPathComponent("photos")
            .appendingPathComponent(photo.id.uuidString + ".jpg")
    }

    private func persist() {
        guard let storeURL, let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: storeURL, options: .atomic)
    }

    private func gate() throws {
        if controls?.simulateOffline == true { throw BackendError.network }
    }

    private func me() throws -> UserProfile {
        guard let id = state.signedInUserID, let profile = user(id) else { throw BackendError.notSignedIn }
        return profile
    }

    private func user(_ id: UUID) -> UserProfile? { state.users.first { $0.id == id } }
    private func system(_ id: UUID) -> RankingSystem? { state.systems.first { $0.id == id } }

    private func canView(_ visit: Visit, viewer: UUID) -> Bool {
        VisibilityRules.canView(visit, viewerID: viewer, viewerFollowsAuthor: state.follows.contains {
            $0.followerID == viewer && $0.followeeID == visit.userID
        })
    }

    private func ownedSystemIndex(_ id: UUID, owner: UUID) throws -> Int {
        guard let index = state.systems.firstIndex(where: { $0.id == id }) else { throw BackendError.notFound }
        guard state.systems[index].ownerID == owner else {
            throw BackendError.notAllowed(state.systems[index].isStandard
                ? "Standard systems can't be changed. Editing one makes a personal copy instead."
                : "You can only change ranking systems you own.")
        }
        return index
    }

    private func ownedVisitIndex(_ id: UUID) throws -> Int {
        let owner = try me().id
        guard let index = state.visits.firstIndex(where: { $0.id == id }) else { throw BackendError.notFound }
        guard state.visits[index].userID == owner else {
            throw BackendError.notAllowed("You can only change your own visits.")
        }
        return index
    }

    private func apply(_ details: VisitDetails, to visit: inout Visit) throws {
        if let spend = details.spendPerPerson, spend < 0 {
            throw BackendError.invalid("Amount spent can't be negative.")
        }
        guard details.visitedOn <= Date.now.addingTimeInterval(86_400) else {
            throw BackendError.invalid("A visit can't be dated in the future.")
        }
        visit.visitedOn = details.visitedOn
        visit.notes = details.notes.trimmed
        visit.dishes = details.dishes.map(\.trimmed).filter { !$0.isEmpty }
        visit.spendPerPerson = details.spendPerPerson
        visit.currencyCode = details.currencyCode
        visit.visibility = details.visibility
    }
}
