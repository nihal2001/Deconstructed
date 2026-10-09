import Foundation
import Observation

enum AppTab: Hashable {
    case discover, map, rankings, friends, profile
}

struct RatingInput {
    var versionID: UUID
    var scores: [UUID: Int]
    var complete: Bool
}

/// Everything the signed-in user owns, loaded once and kept in step with the backend.
/// Screens read from here and call its methods; they never talk to a service directly.
@MainActor
@Observable
final class AppModel {
    enum Phase {
        case launching, signedOut, signedIn
    }

    let environment: AppEnvironment
    let discovery: DiscoveryModel
    let location = LocationService()

    private(set) var phase: Phase = .launching
    private(set) var profile: UserProfile?
    private(set) var systems: [UUID: RankingSystem] = [:]
    private(set) var versions: [UUID: SystemVersion] = [:]
    private(set) var restaurants: [UUID: RestaurantRef] = [:]
    private(set) var saved: [SavedPlace] = []
    private(set) var visits: [Visit] = []
    /// Provider content, held in memory for this launch only.
    private(set) var places: [String: Place] = [:]
    private(set) var placeLoadError: PlacesError?
    /// Changing this makes rows retry a failed place lookup.
    private(set) var placeReloadToken = 0

    var selectedTab: AppTab = .discover
    /// Set by "View on map": the Map tab centres on and selects this place.
    var mapFocusPlaceID: String?
    var toast: String?

    @ObservationIgnored private var placeTasks: [String: Task<Place?, Never>] = [:]

    var isDemo: Bool { environment.isDemo }
    private var backend: BackendService { environment.backend }
    private var provider: PlacesProvider { environment.places }

    init(environment: AppEnvironment) {
        self.environment = environment
        discovery = DiscoveryModel(provider: environment.places, config: environment.config)
        discovery.onResults = { [weak self] in self?.remember($0) }
    }

    // MARK: Session

    func bootstrap() async {
        do {
            if let profile = try await backend.restoreSession() {
                self.profile = profile
                try await loadAll()
                phase = .signedIn
            } else {
                phase = .signedOut
            }
        } catch {
            // A failed refresh at launch should not strand the user on a spinner.
            phase = profile == nil ? .signedOut : .signedIn
            toast = error.localizedDescription
        }
    }

    func signInDemo() async throws {
        profile = try await backend.signInDemo()
        // Give the demo somewhere to look so search and the map work without location access.
        if location.manualArea == nil, location.access != .granted {
            location.manualArea = NamedArea(name: "Hayes Valley", coordinate: DemoCatalog.home)
        }
        try await loadAll()
        phase = .signedIn
    }

    func signInWithApple(idToken: String, nonce: String, displayName: String?) async throws {
        profile = try await backend.signInWithApple(idToken: idToken, nonce: nonce, displayName: displayName)
        try await loadAll()
        phase = .signedIn
    }

    func signOut() async {
        try? await backend.signOut()
        clear()
    }

    func deleteAccount() async throws {
        try await backend.deleteAccount()
        clear()
    }

    func resetDemo() async {
        environment.demoBackend?.resetToSeed()
        try? await loadAll()
        toast = "Demo data reset"
    }

    func loadAll() async throws {
        if let fresh = try await backend.restoreSession() { profile = fresh }
        async let catalog = backend.loadCatalog()
        async let savedPlaces = backend.loadSaved()
        async let myVisits = backend.loadMyVisits()
        let (loadedCatalog, loadedSaved, loadedVisits) = try await (catalog, savedPlaces, myVisits)
        systems = [:]
        versions = [:]
        merge(loadedCatalog)
        saved = loadedSaved
        visits = loadedVisits
        try await loadRestaurants(ids: loadedSaved.map(\.restaurantID) + loadedVisits.map(\.restaurantID))
    }

    private func clear() {
        profile = nil
        systems = [:]
        versions = [:]
        restaurants = [:]
        saved = []
        visits = []
        discovery.reset()
        selectedTab = .discover
        phase = .signedOut
    }

    func updateProfile(_ change: (inout UserProfile) -> Void) async throws {
        guard var updated = profile else { throw BackendError.notSignedIn }
        change(&updated)
        profile = try await backend.updateProfile(updated)
    }

    // MARK: Ranking systems

    func version(_ id: UUID?) -> SystemVersion? { id.flatMap { versions[$0] } }
    func currentVersion(of system: RankingSystem) -> SystemVersion? { version(system.currentVersionID) }

    func versions(of systemID: UUID) -> [SystemVersion] {
        versions.values.filter { $0.systemID == systemID }.sorted { $0.number > $1.number }
    }

    func isArchived(_ system: RankingSystem) -> Bool {
        system.isStandard ? (profile?.archivedStandardSystemIDs.contains(system.id) ?? false) : system.isArchived
    }

    func isMine(_ system: RankingSystem) -> Bool {
        system.isStandard || system.ownerID == profile?.id
    }

    /// Standard systems and the user's own, in a stable order.
    var mySystems: [RankingSystem] {
        systems.values.filter(isMine).sorted {
            if $0.isStandard != $1.isStandard { return $0.isStandard }
            return $0.isStandard ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        }
    }

    /// Systems that can be chosen for a new rating.
    var selectableSystems: [RankingSystem] {
        mySystems.filter { $0.currentVersionID != nil && !isArchived($0) }
    }

    var draftSystems: [RankingSystem] { mySystems.filter { $0.isDraftOnly && !isArchived($0) } }
    var archivedSystems: [RankingSystem] { mySystems.filter(isArchived) }

    var defaultSystem: RankingSystem? {
        selectableSystems.first { $0.id == profile?.defaultSystemID } ?? selectableSystems.first
    }

    func setDefaultSystem(_ system: RankingSystem) async throws {
        try await updateProfile { $0.defaultSystemID = system.id }
    }

    func systemName(_ systemID: UUID) -> String { systems[systemID]?.name ?? "Unknown system" }

    /// “8/10 · Fast Casual”, the form every completed rating is shown in.
    func ratingLabel(_ revision: RatingRevision) -> String {
        "\(revision.total.map(String.init) ?? "–")/\(RankingRules.totalPoints) · \(systemName(revision.systemID))"
    }

    func hasRatings(_ system: RankingSystem) -> Bool {
        visits.contains { $0.revisions.contains { $0.systemID == system.id } }
    }

    /// Saves unpublished edits. Editing a standard system starts a personal copy instead.
    @discardableResult
    func saveSystemDraft(_ draft: SystemDraft, for system: RankingSystem?) async throws -> RankingSystem {
        let saved: RankingSystem
        if let system, !system.isStandard {
            saved = try await backend.saveDraft(systemID: system.id, draft: draft, forkedFrom: nil)
        } else {
            saved = try await backend.saveDraft(systemID: nil, draft: draft, forkedFrom: system?.id)
        }
        systems[saved.id] = saved
        return saved
    }

    /// Publishes a draft. For a standard system this creates the user's personal copy, puts
    /// the standard one away, and moves the default across so nothing changes underfoot.
    @discardableResult
    func publishSystem(_ draft: SystemDraft, for system: RankingSystem?) async throws -> RankingSystem {
        let issues = SystemValidator.issues(for: draft)
        if let issue = issues.first { throw BackendError.invalid(issue.message) }

        let target = (system?.isStandard ?? true) ? try await saveSystemDraft(draft, for: system) : system!
        merge(try await backend.publish(systemID: target.id, draft: draft))

        if let system, system.isStandard {
            let wasDefault = defaultSystem?.id == system.id
            try await updateProfile {
                if !$0.archivedStandardSystemIDs.contains(system.id) { $0.archivedStandardSystemIDs.append(system.id) }
                if wasDefault { $0.defaultSystemID = target.id }
            }
        }
        return systems[target.id] ?? target
    }

    func duplicateSystem(_ system: RankingSystem) async throws -> RankingSystem {
        let source = system.editableDraft(currentVersion: currentVersion(of: system))
        let copy = source.duplicated(named: uniqueName(basedOn: "\(system.name) copy"))
        let created = try await backend.saveDraft(systemID: nil, draft: copy, forkedFrom: nil)
        systems[created.id] = created
        return created
    }

    func setArchived(_ system: RankingSystem, archived: Bool) async throws {
        if system.isStandard {
            try await updateProfile {
                $0.archivedStandardSystemIDs.removeAll { $0 == system.id }
                if archived { $0.archivedStandardSystemIDs.append(system.id) }
            }
        } else {
            systems[system.id] = try await backend.setArchived(systemID: system.id, archived: archived)
        }
        if archived, profile?.defaultSystemID == system.id, let fallback = selectableSystems.first {
            try await setDefaultSystem(fallback)
        }
    }

    func deleteSystem(_ system: RankingSystem) async throws {
        try await backend.deleteSystem(systemID: system.id)
        systems[system.id] = nil
        versions = versions.filter { $0.value.systemID != system.id }
    }

    private func uniqueName(basedOn base: String) -> String {
        let taken = Set(mySystems.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        return (2...99).lazy.map { "\(base) \($0)" }.first { !taken.contains($0.lowercased()) } ?? base
    }

    private func merge(_ catalog: SystemCatalog) {
        for system in catalog.systems { systems[system.id] = system }
        for version in catalog.versions { versions[version.id] = version }
    }

    /// Fetches rubric definitions behind other people's ratings so they can be shown in full.
    func ensureDefinitions(for visits: [Visit]) async {
        let missing = Set(visits.flatMap(\.revisions).map(\.versionID)).filter { versions[$0] == nil }
        guard !missing.isEmpty, let catalog = try? await backend.loadDefinitions(versionIDs: Array(missing)) else { return }
        merge(catalog)
    }

    // MARK: Restaurants and places

    func restaurant(forPlaceID placeID: String) -> RestaurantRef? {
        restaurants.values.first { $0.providerPlaceID == placeID && $0.provider == provider.providerKey }
    }

    func place(for restaurantID: UUID) -> Place? {
        restaurants[restaurantID].flatMap { places[$0.providerPlaceID] }
    }

    func displayName(for restaurantID: UUID) -> String {
        place(for: restaurantID)?.name ?? (placeLoadError == nil ? "Loading…" : "Name unavailable")
    }

    func remember(_ loaded: [Place]) {
        for place in loaded {
            places[place.placeID] = places[place.placeID]?.merged(with: place) ?? place
        }
    }

    func loadRestaurants(ids: [UUID]) async throws {
        let missing = Set(ids).filter { restaurants[$0] == nil }
        guard !missing.isEmpty else { return }
        for ref in try await backend.loadRestaurants(ids: Array(missing)) { restaurants[ref.id] = ref }
    }

    /// Loads provider content for a place if it isn't already in memory at this level.
    /// Concurrent callers share one request, and a quota error pauses automatic retries.
    @discardableResult
    func ensurePlace(_ placeID: String, level: PlaceDetailLevel = .core, session: PlacesSession? = nil) async -> Place? {
        if let cached = places[placeID], cached.level >= level, level != .location || cached.coordinate != nil {
            return cached
        }
        if placeLoadError != nil, session == nil { return places[placeID] }

        let key = "\(placeID)|\(level.rawValue)"
        if let running = placeTasks[key] { return await running.value }
        let task = Task { [provider] () -> Place? in
            do {
                let place = try await provider.details(placeID: placeID, level: level, session: session)
                self.remember([place])
                return self.places[placeID]
            } catch {
                self.placeLoadError = (error as? PlacesError) ?? .other(error.localizedDescription)
                return self.places[placeID]
            }
        }
        placeTasks[key] = task
        let result = await task.value
        placeTasks[key] = nil
        return result
    }

    func ensurePlace(for restaurantID: UUID, level: PlaceDetailLevel = .core) async {
        guard let ref = restaurants[restaurantID] else { return }
        await ensurePlace(ref.providerPlaceID, level: level)
    }

    func retryPlaceLoads() {
        placeLoadError = nil
        placeReloadToken += 1
    }

    /// A coordinate for drawing a saved pin. Uses the stored copy while it is inside the
    /// allowed caching window, and otherwise asks the provider for the location only.
    func pinCoordinate(for ref: RestaurantRef) async -> Coordinate? {
        if let coordinate = places[ref.providerPlaceID]?.coordinate ?? ref.freshCoordinate() { return coordinate }
        guard let coordinate = await ensurePlace(ref.providerPlaceID, level: .location)?.coordinate else { return nil }
        if let updated = try? await backend.cacheCoordinate(restaurantID: ref.id, coordinate: coordinate) {
            restaurants[ref.id] = updated
        }
        return coordinate
    }

    private func ensureRestaurant(for place: Place) async throws -> RestaurantRef {
        if let existing = restaurant(forPlaceID: place.placeID) { return existing }
        let ref = try await backend.ensureRestaurant(provider: provider.providerKey, placeID: place.placeID,
                                                     coordinate: place.coordinate)
        restaurants[ref.id] = ref
        return ref
    }

    // MARK: Saved places

    func isSaved(placeID: String) -> Bool {
        guard let ref = restaurant(forPlaceID: placeID) else { return false }
        return saved.contains { $0.restaurantID == ref.id }
    }

    func setSaved(_ place: Place, saved shouldSave: Bool) async throws {
        let ref = try await ensureRestaurant(for: place)
        try await backend.setSaved(restaurantID: ref.id, saved: shouldSave)
        saved.removeAll { $0.restaurantID == ref.id }
        if shouldSave { saved.append(SavedPlace(restaurantID: ref.id, savedAt: .now)) }
    }

    // MARK: Visits

    func visits(forPlaceID placeID: String) -> [Visit] {
        guard let ref = restaurant(forPlaceID: placeID) else { return [] }
        return visits.filter { $0.restaurantID == ref.id }.sorted { RankingEngine.isLater($0, than: $1) }
    }

    func hasCompletedVisit(placeID: String) -> Bool {
        visits(forPlaceID: placeID).contains(where: \.isCompleted)
    }

    var draftVisits: [Visit] {
        visits.filter { !$0.isCompleted }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var visitedRestaurantIDs: Set<UUID> {
        Set(visits.filter(\.isCompleted).map(\.restaurantID))
    }

    func ranked(scope: SystemScope) -> [RankedRestaurant] {
        RankingEngine.rank(visits: visits, scope: scope) { [self] in place(for: $0)?.name ?? "" }
    }

    /// Creates or updates a visit, its photos and, optionally, its rating in one go.
    /// The rating is validated here first and again by the backend, which owns the total.
    @discardableResult
    func saveVisit(existing: Visit?, place: Place, details: VisitDetails, rating: RatingInput?,
                   newPhotos: [Data] = [], removedPhotoIDs: [UUID] = []) async throws -> Visit {
        if let rating {
            guard let version = versions[rating.versionID] else { throw BackendError.notFound }
            let issues = RatingEngine.issues(scores: rating.scores, version: version, requireComplete: rating.complete)
            if let issue = issues.first { throw BackendError.invalid(issue.message) }
        }

        let ref = try await ensureRestaurant(for: place)
        var visit: Visit
        if let existing {
            visit = try await backend.updateVisit(id: existing.id, details: details)
        } else {
            visit = try await backend.createVisit(restaurantID: ref.id, details: details)
        }
        upsert(visit)
        for id in removedPhotoIDs {
            visit = try await backend.removePhoto(visitID: visit.id, photoID: id)
        }
        for data in newPhotos {
            visit = try await backend.addPhoto(visitID: visit.id, jpeg: data)
        }
        if let rating {
            visit = try await backend.saveRating(visitID: visit.id, versionID: rating.versionID,
                                                 scores: rating.scores, complete: rating.complete)
        }
        upsert(visit)

        // Once a place has a completed visit it is "Visited", not "Want to try".
        if visit.isCompleted, saved.contains(where: { $0.restaurantID == ref.id }) {
            try? await backend.setSaved(restaurantID: ref.id, saved: false)
            saved.removeAll { $0.restaurantID == ref.id }
        }
        return visit
    }

    func deleteVisit(_ visit: Visit) async throws {
        try await backend.deleteVisit(id: visit.id)
        visits.removeAll { $0.id == visit.id }
    }

    func discardDraftRating(_ visit: Visit) async throws {
        upsert(try await backend.discardDraftRating(visitID: visit.id))
    }

    func photoData(_ photo: VisitPhoto) async -> Data? {
        try? await backend.photoData(photo)
    }

    private func upsert(_ visit: Visit) {
        if let index = visits.firstIndex(where: { $0.id == visit.id }) {
            visits[index] = visit
        } else {
            visits.append(visit)
        }
    }

    // MARK: Friends and community

    func communityScores(placeID: String) async throws -> [CommunityScore] {
        try await backend.communityScores(provider: provider.providerKey, placeID: placeID)
    }

    func loadFeed() async throws -> [FeedItem] {
        let feed = try await backend.loadFeed()
        try await loadRestaurants(ids: feed.map(\.visit.restaurantID))
        await ensureDefinitions(for: feed.map(\.visit))
        return feed
    }

    func loadVisits(of user: UserProfile) async throws -> [Visit] {
        let loaded = try await backend.loadVisits(ofUser: user.id)
        try await loadRestaurants(ids: loaded.map(\.restaurantID))
        await ensureDefinitions(for: loaded)
        return loaded
    }

    func searchUsers(_ query: String) async throws -> [UserProfile] { try await backend.searchUsers(query) }
    func loadFollowing() async throws -> [UserProfile] { try await backend.loadFollowing() }
    func loadFollowers() async throws -> [UserProfile] { try await backend.loadFollowers() }
    func setFollowing(_ user: UserProfile, following: Bool) async throws {
        try await backend.setFollowing(userID: user.id, following: following)
    }
    func removeFollower(_ user: UserProfile) async throws { try await backend.removeFollower(userID: user.id) }

    // MARK: Navigation helpers

    func showOnMap(placeID: String) {
        mapFocusPlaceID = placeID
        selectedTab = .map
    }
}
