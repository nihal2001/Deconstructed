import XCTest
@testable import Deconstructed

/// A small fictional world: "me" plus numbered people, the three standard systems, and one
/// restaurant. Tests add visits through the same backend calls the app uses.
@MainActor
struct World {
    let backend: DemoBackend
    let restaurant: RestaurantRef
    let me = DemoSeed.meID

    static func person(_ n: Int) -> UUID {
        UUID(uuidString: "AAAAAAAA-0000-4000-8000-\(String(format: "%012d", n))")!
    }

    init(people: Int = 8) async throws {
        var state = DemoState()
        state.systems = StarterSystems.catalog.systems
        state.versions = StarterSystems.catalog.versions
        state.users = [UserProfile(id: DemoSeed.meID, username: "me", displayName: "Me", defaultSystemID: StarterSystems.general)]
            + (1...people).map { UserProfile(id: World.person($0), username: "person\($0)", displayName: "Person \($0)") }
        state.signedInUserID = DemoSeed.meID
        backend = DemoBackend(persist: false, seed: state)
        restaurant = try await backend.ensureRestaurant(provider: "demo", placeID: "demo-test", coordinate: nil)
    }

    func version(_ systemID: UUID) -> SystemVersion {
        StarterSystems.catalog.versions.first { $0.systemID == systemID }!
    }

    var general: SystemVersion { version(StarterSystems.general) }
    var fineDining: SystemVersion { version(StarterSystems.fineDining) }
    var fastCasual: SystemVersion { version(StarterSystems.fastCasual) }

    /// Logs a completed visit as `user`, then switches back to "me".
    @discardableResult
    func rate(as user: UUID, _ version: SystemVersion, _ points: [Int], daysAgo: Int = 1,
              visibility: Visibility = .everyone, restaurant: RestaurantRef? = nil, complete: Bool = true) async throws -> Visit {
        backend.impersonate(user)
        defer { backend.impersonate(me) }
        var details = VisitDetails()
        details.visitedOn = Date.now.addingTimeInterval(TimeInterval(-daysAgo) * 86_400)
        details.visibility = visibility
        let visit = try await backend.createVisit(restaurantID: (restaurant ?? self.restaurant).id, details: details)
        return try await backend.saveRating(visitID: visit.id, versionID: version.id,
                                            scores: World.scores(version, points), complete: complete)
    }

    /// Creates and publishes a personal system as the signed-in user; returns its first version.
    func publishNew(_ draft: SystemDraft, forkedFrom: UUID? = nil) async throws -> (system: RankingSystem, version: SystemVersion) {
        let created = try await backend.saveDraft(systemID: nil, draft: draft, forkedFrom: forkedFrom)
        let catalog = try await backend.publish(systemID: created.id, draft: draft)
        return (catalog.systems[0], catalog.versions[0])
    }

    func myVisit(_ id: UUID) async throws -> Visit? {
        try await backend.loadMyVisits().first { $0.id == id }
    }

    func mySystem(_ id: UUID) async throws -> RankingSystem? {
        try await backend.loadCatalog().systems.first { $0.id == id }
    }

    static func scores(_ version: SystemVersion, _ points: [Int]) -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: zip(version.criteria.map(\.id), points))
    }

    func follow(_ follower: UUID, _ followee: UUID) async throws {
        backend.impersonate(follower)
        defer { backend.impersonate(me) }
        try await backend.setFollowing(userID: followee, following: true)
    }
}

/// Records every provider call so tests can assert on what was, and was not, requested.
@MainActor
final class RecordingPlacesProvider: PlacesProvider {
    let providerKey = "demo"
    let isDemo = true

    private(set) var autocompleteQueries: [String] = []
    private(set) var autocompleteSessions: [UUID] = []
    private(set) var textSearches: [String] = []
    private(set) var nearbySearches = 0
    private(set) var detailRequests: [(placeID: String, level: PlaceDetailLevel, session: UUID?)] = []
    var failure: PlacesError?

    var totalRequests: Int { autocompleteQueries.count + textSearches.count + nearbySearches + detailRequests.count }

    private let base = DemoPlacesProvider(controls: DemoControls(), latency: .zero)

    func autocomplete(query: String, near: Coordinate?, session: PlacesSession) async throws -> [PlaceSuggestion] {
        autocompleteQueries.append(query)
        autocompleteSessions.append(session.id)
        if let failure { throw failure }
        return try await base.autocomplete(query: query, near: near, session: session)
    }

    func searchText(_ query: String, near: Coordinate?) async throws -> [Place] {
        textSearches.append(query)
        if let failure { throw failure }
        return try await base.searchText(query, near: near)
    }

    func searchNearby(center: Coordinate, radiusMeters: Double) async throws -> [Place] {
        nearbySearches += 1
        if let failure { throw failure }
        return try await base.searchNearby(center: center, radiusMeters: radiusMeters)
    }

    func details(placeID: String, level: PlaceDetailLevel, session: PlacesSession?) async throws -> Place {
        detailRequests.append((placeID, level, session?.id))
        if let failure { throw failure }
        return try await base.details(placeID: placeID, level: level, session: session)
    }
}

extension XCTestCase {
    /// Asserts that an async call throws, and hands back the error for inspection.
    @MainActor
    @discardableResult
    func assertThrows<T>(_ expression: @autoclosure () async throws -> T, _ message: String = "",
                         file: StaticString = #filePath, line: UInt = #line) async -> Error? {
        do {
            _ = try await expression()
            XCTFail("Expected an error. \(message)", file: file, line: line)
            return nil
        } catch {
            return error
        }
    }
}
