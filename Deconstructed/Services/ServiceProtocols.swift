import Foundation

// Provider integrations sit behind these two protocols so Google or Supabase can be replaced
// without touching the screens. `Demo*` and the live types are the two implementations.

// MARK: - Places

enum PlacesError: LocalizedError, Equatable {
    /// The provider says the project's quota is used up.
    case quotaExhausted
    /// This app's own guard rail (see `RequestMonitor`) stopped the request before it was sent.
    case localLimitReached(retryAfter: TimeInterval)
    case network
    case notConfigured(String)
    case notFound
    case other(String)

    var errorDescription: String? {
        switch self {
        case .quotaExhausted:
            "Restaurant search has reached its usage limit for now. Your saved places and rankings still work. Try again later."
        case .localLimitReached(let retryAfter):
            retryAfter > 90
                ? "This device has made a lot of restaurant searches today, so search is paused to keep costs down. It resets tomorrow."
                : "Too many searches in a short time. Try again in \(Int(retryAfter.rounded(.up))) seconds."
        case .network:
            "Couldn't reach the restaurant search service. Check your connection and try again."
        case .notConfigured(let detail):
            "Restaurant search isn't set up: \(detail)"
        case .notFound:
            "That restaurant's listing is no longer available from the provider. Your visits and scores are still here."
        case .other(let detail):
            detail
        }
    }

    var isRetryable: Bool {
        switch self {
        case .notConfigured, .notFound: false
        default: true
        }
    }
}

/// One autocomplete session: starts with the first keystroke request and ends when the user
/// picks a suggestion (the details request) or abandons the search. Never reused afterwards.
final class PlacesSession {
    let id = UUID()
    /// Provider-specific token object, created lazily by the provider.
    var providerToken: AnyObject?
}

@MainActor
protocol PlacesProvider: AnyObject {
    /// Stored next to place IDs so records from different providers never collide.
    var providerKey: String { get }
    var isDemo: Bool { get }

    func autocomplete(query: String, near: Coordinate?, session: PlacesSession) async throws -> [PlaceSuggestion]
    /// Returns `.core` level places, so opening a result needs no further request.
    func searchText(_ query: String, near: Coordinate?) async throws -> [Place]
    func searchNearby(center: Coordinate, radiusMeters: Double) async throws -> [Place]
    /// Passing the autocomplete session closes it, which is what makes the session billable once.
    func details(placeID: String, level: PlaceDetailLevel, session: PlacesSession?) async throws -> Place
}

// MARK: - Backend

enum BackendError: LocalizedError, Equatable {
    case notSignedIn
    case notAllowed(String)
    case invalid(String)
    case notFound
    case network
    case other(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "You're signed out. Sign in again to continue."
        case .notAllowed(let detail): detail
        case .invalid(let detail): detail
        case .notFound: "That item no longer exists."
        case .network: "Couldn't reach the server. Check your connection and try again."
        case .other(let detail): detail
        }
    }
}

@MainActor
protocol BackendService: AnyObject {
    var isDemo: Bool { get }

    // Session
    func restoreSession() async throws -> UserProfile?
    func signInWithApple(idToken: String, nonce: String, displayName: String?) async throws -> UserProfile
    func signInDemo() async throws -> UserProfile
    func signOut() async throws
    func deleteAccount() async throws
    func updateProfile(_ profile: UserProfile) async throws -> UserProfile

    // Ranking systems
    /// Standard systems plus everything the signed-in user owns, including drafts and archives.
    func loadCatalog() async throws -> SystemCatalog
    /// Definitions behind other people's ratings, readable only where the rating itself is.
    func loadDefinitions(versionIDs: [UUID]) async throws -> SystemCatalog
    /// Creates (when `systemID` is nil) or updates a personal system's unpublished draft.
    func saveDraft(systemID: UUID?, draft: SystemDraft, forkedFrom: UUID?) async throws -> RankingSystem
    /// Validates the draft and publishes it. Adds a version only if the criteria changed.
    func publish(systemID: UUID, draft: SystemDraft) async throws -> SystemCatalog
    func setArchived(systemID: UUID, archived: Bool) async throws -> RankingSystem
    /// Permanently removes a personal system. Refused once any rating has used it.
    func deleteSystem(systemID: UUID) async throws

    // Restaurants and saved places
    func ensureRestaurant(provider: String, placeID: String, coordinate: Coordinate?) async throws -> RestaurantRef
    func loadRestaurants(ids: [UUID]) async throws -> [RestaurantRef]
    func cacheCoordinate(restaurantID: UUID, coordinate: Coordinate) async throws -> RestaurantRef
    func loadSaved() async throws -> [SavedPlace]
    func setSaved(restaurantID: UUID, saved: Bool) async throws

    // Visits and ratings
    func loadMyVisits() async throws -> [Visit]
    func createVisit(restaurantID: UUID, details: VisitDetails) async throws -> Visit
    func updateVisit(id: UUID, details: VisitDetails) async throws -> Visit
    func deleteVisit(id: UUID) async throws
    /// The only way scores are written. The backend re-validates them and computes the total;
    /// a client-supplied total is not part of this call on purpose.
    func saveRating(visitID: UUID, versionID: UUID, scores: [UUID: Int], complete: Bool) async throws -> Visit
    func discardDraftRating(visitID: UUID) async throws -> Visit
    func addPhoto(visitID: UUID, jpeg: Data) async throws -> Visit
    func removePhoto(visitID: UUID, photoID: UUID) async throws -> Visit
    func photoData(_ photo: VisitPhoto) async throws -> Data

    // Friends and community
    func searchUsers(_ query: String) async throws -> [UserProfile]
    func loadFollowing() async throws -> [UserProfile]
    func loadFollowers() async throws -> [UserProfile]
    func setFollowing(userID: UUID, following: Bool) async throws
    func removeFollower(userID: UUID) async throws
    func loadFeed() async throws -> [FeedItem]
    /// Another person's completed visits, limited to those the signed-in user may read.
    func loadVisits(ofUser userID: UUID) async throws -> [Visit]
    func communityScores(provider: String, placeID: String) async throws -> [CommunityScore]
}
