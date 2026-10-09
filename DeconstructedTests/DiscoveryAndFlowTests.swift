import XCTest
@testable import Deconstructed

@MainActor
final class DiscoveryAndFlowTests: XCTestCase {
    private func config(debounceMs: Int = 30) -> AppConfig {
        var config = AppConfig()
        config.autocompleteMinCharacters = 3
        config.autocompleteDebounce = .milliseconds(debounceMs)
        return config
    }

    private func settle(_ milliseconds: Int = 150) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    private let center = Coordinate(latitude: 37.7763, longitude: -122.4242)

    // MARK: Cost rules

    func testMovingTheMapNeverTriggersASearch() async {
        let provider = RecordingPlacesProvider()
        let discovery = DiscoveryModel(provider: provider, config: config())

        for step in 0..<40 {
            discovery.mapMoved(center: Coordinate(latitude: center.latitude + Double(step) * 0.01, longitude: center.longitude),
                               radiusMeters: 1_000 + Double(step) * 250)
        }
        await settle()

        XCTAssertEqual(provider.totalRequests, 0, "panning and zooming must not call the provider")
        XCTAssertTrue(discovery.results.isEmpty)
        XCTAssertTrue(discovery.mapMovedSinceSearch)
        XCTAssertNotNil(discovery.visibleMapArea)

        // Only the explicit action searches, exactly once.
        await discovery.searchArea(center: center, radiusMeters: 1_500)
        XCTAssertEqual(provider.nearbySearches, 1)
        XCTAssertEqual(provider.totalRequests, 1)
        XCTAssertFalse(discovery.results.isEmpty)
        XCTAssertFalse(discovery.mapMovedSinceSearch)

        discovery.mapMoved(center: Coordinate(latitude: 37.80, longitude: -122.41), radiusMeters: 1_500)
        await settle()
        XCTAssertEqual(provider.totalRequests, 1)
        XCTAssertTrue(discovery.mapMovedSinceSearch, "the button is offered again, but nothing is fetched")
    }

    func testAutocompleteIsDebouncedAndNeedsMinimumLength() async {
        let provider = RecordingPlacesProvider()
        let discovery = DiscoveryModel(provider: provider, config: config(debounceMs: 60))

        for text in ["t", "ta"] {
            discovery.query = text
            discovery.queryChanged(near: center)
        }
        await settle()
        XCTAssertEqual(provider.autocompleteQueries, [], "too short to send")

        // Fast typing: only the text left after the pause is sent.
        for text in ["tac", "taco", "tacos"] {
            discovery.query = text
            discovery.queryChanged(near: center)
        }
        await settle(250)
        XCTAssertEqual(provider.autocompleteQueries, ["tacos"])
        XCTAssertFalse(discovery.suggestions.isEmpty)
        XCTAssertTrue(discovery.suggestions.allSatisfy(\.isDemo), "demo records are always marked as demo")
    }

    func testOneSessionCoversTypingAndIsClosedBySelection() async throws {
        let provider = RecordingPlacesProvider()
        let model = AppModel(environment: .ephemeralDemo(places: provider))
        try await model.signInDemo()
        let discovery = DiscoveryModel(provider: provider, config: config())

        discovery.query = "saltm"
        discovery.queryChanged(near: center)
        await settle()
        discovery.query = "saltmarsh"
        discovery.queryChanged(near: center)
        await settle()
        XCTAssertEqual(provider.autocompleteSessions.count, 2)
        XCTAssertEqual(Set(provider.autocompleteSessions).count, 1, "keystrokes share one session token")

        let suggestion = try XCTUnwrap(discovery.suggestions.first)
        let session = try XCTUnwrap(discovery.takeSessionForSelection())
        await model.ensurePlace(suggestion.placeID, level: .core, session: session)
        XCTAssertEqual(provider.detailRequests.last?.session, provider.autocompleteSessions.first, "details closes the session")
        XCTAssertNil(discovery.takeSessionForSelection(), "a closed session is never handed out again")

        // The next search starts a new session.
        discovery.query = "pizza"
        discovery.queryChanged(near: center)
        await settle()
        XCTAssertEqual(Set(provider.autocompleteSessions).count, 2)

        // Opening the place again reuses what is in memory: no second details request.
        let before = provider.detailRequests.count
        await model.ensurePlace(suggestion.placeID, level: .core)
        XCTAssertEqual(provider.detailRequests.count, before)
    }

    func testSearchResultsAreReusedWithoutAnotherDetailsRequest() async throws {
        let provider = RecordingPlacesProvider()
        let model = AppModel(environment: .ephemeralDemo(places: provider))
        try await model.signInDemo()

        model.discovery.query = "ramen"
        await model.discovery.searchText(near: center)
        let result = try XCTUnwrap(model.discovery.results.first)
        XCTAssertEqual(provider.textSearches, ["ramen"])

        let place = await model.ensurePlace(result.placeID, level: .core)
        XCTAssertEqual(place?.name, result.name)
        XCTAssertTrue(provider.detailRequests.isEmpty, "fields returned by the search are reused when the profile opens")

        // Richer details are a separate, explicit step.
        await model.ensurePlace(result.placeID, level: .extended)
        XCTAssertEqual(provider.detailRequests.map(\.level), [.extended])
    }

    // MARK: Failure handling

    func testQuotaExhaustionShowsAMessageAndCanBeRetried() async {
        let provider = RecordingPlacesProvider()
        let discovery = DiscoveryModel(provider: provider, config: config())
        provider.failure = .quotaExhausted

        await discovery.searchArea(center: center, radiusMeters: 1_500)
        XCTAssertEqual(discovery.error, .quotaExhausted)
        XCTAssertTrue(discovery.canRetry)
        XCTAssertTrue(discovery.results.isEmpty)
        XCTAssertFalse(discovery.isSearching)
        XCTAssertEqual(PlacesError.quotaExhausted.errorDescription?.contains("usage limit"), true)

        provider.failure = nil
        await discovery.retry()
        XCTAssertNil(discovery.error)
        XCTAssertFalse(discovery.results.isEmpty)
        XCTAssertEqual(provider.nearbySearches, 2)
    }

    func testNetworkFailureKeepsExistingDataAndRecovers() async throws {
        let environment = AppEnvironment.ephemeralDemo()
        let model = AppModel(environment: environment)
        try await model.signInDemo()
        let visitsBefore = model.visits.count
        let place = try XCTUnwrap(DemoCatalog.restaurants.first { $0.placeID == "demo-fig-ember" }?.place)

        environment.demoControls.simulateOffline = true
        model.discovery.query = "tacos"
        await model.discovery.searchText(near: center)
        XCTAssertEqual(model.discovery.error, .network)
        await assertThrows(try await model.setSaved(place, saved: true))
        let general = try XCTUnwrap(model.defaultSystem.flatMap(model.currentVersion(of:)))
        await assertThrows(try await model.saveVisit(
            existing: nil, place: place, details: VisitDetails(),
            rating: RatingInput(versionID: general.id, scores: World.scores(general, [4, 2, 2, 1]), complete: true)))
        XCTAssertEqual(model.visits.count, visitsBefore, "a failed save leaves local state untouched")
        XCTAssertFalse(model.isSaved(placeID: place.placeID))
        XCTAssertFalse(model.ranked(scope: .allSystems).isEmpty, "rankings still work offline")

        environment.demoControls.simulateOffline = false
        await model.discovery.retry()
        XCTAssertNil(model.discovery.error)
        XCTAssertFalse(model.discovery.results.isEmpty)
    }

    func testLocalRateLimitsStopRequestsBeforeTheyAreSent() async {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let monitor = RequestMonitor(limits: .init(perMinute: 3, perDay: 5), defaults: nil, now: { now })
        let recorder = RecordingPlacesProvider()
        let metered = MeteredPlacesProvider(base: recorder, monitor: monitor)

        for _ in 0..<3 { _ = try? await metered.searchNearby(center: center, radiusMeters: 1_000) }
        let blocked = await assertThrows(try await metered.searchNearby(center: center, radiusMeters: 1_000))
        guard case .localLimitReached(let retryAfter)? = blocked as? PlacesError else { return XCTFail("expected a local limit") }
        XCTAssertLessThanOrEqual(retryAfter, 60)
        XCTAssertEqual(recorder.nearbySearches, 3, "the fourth request never reached the provider")
        XCTAssertEqual(monitor.blockedToday, 1)

        // A minute later the per-minute window has cleared, until the daily cap is hit.
        now.addTimeInterval(61)
        _ = try? await metered.searchText("tacos", near: nil)
        _ = try? await metered.details(placeID: "demo-bodega-sol", level: .core, session: nil)
        XCTAssertEqual(monitor.todayTotal, 5)
        XCTAssertEqual(monitor.todayCounts[.nearbySearch], 3)
        XCTAssertEqual(monitor.todayCounts[.detailsCore], 1)
        now.addTimeInterval(61)
        let daily = await assertThrows(try await metered.searchText("pizza", near: nil))
        guard case .localLimitReached(let untilTomorrow)? = daily as? PlacesError else { return XCTFail("expected the daily cap") }
        XCTAssertGreaterThan(untilTomorrow, 90)
        XCTAssertEqual(recorder.totalRequests, 5)

        // The cap resets on a new day.
        now.addTimeInterval(86_400)
        _ = try? await metered.searchText("pizza", near: nil)
        XCTAssertEqual(recorder.totalRequests, 6)
        XCTAssertEqual(monitor.todayTotal, 1)
    }

    func testEverythingWorksWithoutLocationAccess() async throws {
        let model = AppModel(environment: .ephemeralDemo())
        try await model.signInDemo()
        // No device location in the test host: a manual area stands in for it.
        model.location.manualArea = NamedArea(name: "Mission", coordinate: Coordinate(latitude: 37.7599, longitude: -122.4148))
        XCTAssertEqual(model.location.originLabel, "Mission")
        let origin = try XCTUnwrap(model.location.searchOrigin)

        await model.discovery.searchArea(center: origin, radiusMeters: 1_500)
        XCTAssertNil(model.discovery.error)
        XCTAssertFalse(model.discovery.results.isEmpty)
        XCTAssertTrue(model.discovery.results.allSatisfy { $0.coordinate.map { $0.distance(to: origin) <= 1_500 } ?? false })
    }

    func testStoredCoordinatesExpireAfterThirtyDays() {
        let now = Date.now
        var ref = RestaurantRef(id: UUID(), provider: "google", providerPlaceID: "abc",
                                cachedCoordinate: center, coordinateCachedAt: now.addingTimeInterval(-29 * 86_400))
        XCTAssertNotNil(ref.freshCoordinate(now: now))
        ref.coordinateCachedAt = now.addingTimeInterval(-31 * 86_400)
        XCTAssertNil(ref.freshCoordinate(now: now), "an expired coordinate is never used; it must be fetched again")
    }

    // MARK: The main journey

    func testSearchSaveLogVisitAndSeeRanking() async throws {
        let model = AppModel(environment: .ephemeralDemo())
        try await model.signInDemo()

        // Search
        model.discovery.query = "Fig"
        await model.discovery.searchText(near: center)
        let place = try XCTUnwrap(model.discovery.results.first { $0.name == "Fig & Ember" })
        XCTAssertTrue(place.isDemo)

        // Save → appears as "want to try" with a coordinate for the map
        try await model.setSaved(place, saved: true)
        XCTAssertTrue(model.isSaved(placeID: place.placeID))
        let ref = try XCTUnwrap(model.restaurant(forPlaceID: place.placeID))
        let pin = await model.pinCoordinate(for: ref)
        XCTAssertNotNil(pin)
        XCTAssertFalse(model.visitedRestaurantIDs.contains(ref.id))

        // Log a visit with the default system; the form starts with nothing selected.
        let system = try XCTUnwrap(model.defaultSystem)
        let version = try XCTUnwrap(model.currentVersion(of: system))
        XCTAssertEqual(system.name, "General")

        // Save as a draft first: not ranked.
        var details = VisitDetails()
        details.notes = "Lamb was great"
        details.dishes = ["Lamb shoulder", " ", "Flatbread"]
        details.spendPerPerson = 48
        let draft = try await model.saveVisit(
            existing: nil, place: place, details: details,
            rating: RatingInput(versionID: version.id, scores: [version.criteria[0].id: 4], complete: false))
        XCTAssertFalse(draft.isCompleted)
        XCTAssertFalse(model.ranked(scope: .allSystems).contains { $0.restaurantID == ref.id })
        XCTAssertTrue(model.isSaved(placeID: place.placeID), "still want-to-try until the rating is submitted")

        // Submit it.
        let submitted = try await model.saveVisit(
            existing: draft, place: place, details: details,
            rating: RatingInput(versionID: version.id, scores: World.scores(version, [4, 2, 1, 1]), complete: true))
        let revision = try XCTUnwrap(submitted.activeRevision)
        XCTAssertEqual(revision.total, 8)
        XCTAssertEqual(model.ratingLabel(revision), "8/10 · General")
        XCTAssertNil(submitted.draftRevision)
        XCTAssertEqual(submitted.dishes, ["Lamb shoulder", "Flatbread"])
        XCTAssertEqual(model.visits.filter { $0.restaurantID == ref.id }.count, 1)

        // Now visited, no longer want-to-try, and ranked under General.
        XCTAssertFalse(model.isSaved(placeID: place.placeID))
        XCTAssertTrue(model.visitedRestaurantIDs.contains(ref.id))
        let ranked = model.ranked(scope: .version(systemID: system.id, versionID: version.id))
        let entry = try XCTUnwrap(ranked.first { $0.restaurantID == ref.id })
        XCTAssertEqual(entry.total, 8)
        // The seeded demo already has two General 8s, so this is a three-way tie.
        let eights = ranked.filter { $0.total == 8 }
        XCTAssertEqual(eights.count, 3)
        XCTAssertEqual(Set(eights.map(\.rank)).count, 1)
        XCTAssertTrue(eights.allSatisfy(\.isTied))

        // Re-rate with Fast Casual: the General rating is kept as history and leaves that ranking.
        let fastCasual = try XCTUnwrap(model.currentVersion(of: try XCTUnwrap(model.systems[StarterSystems.fastCasual])))
        let rerated = try await model.saveVisit(
            existing: submitted, place: place, details: details,
            rating: RatingInput(versionID: fastCasual.id, scores: World.scores(fastCasual, [4, 2, 2]), complete: true))
        XCTAssertEqual(model.ratingLabel(try XCTUnwrap(rerated.activeRevision)), "8/10 · Fast Casual")
        XCTAssertEqual(rerated.supersededRevisions.map(\.total), [8])
        XCTAssertEqual(rerated.supersededRevisions.first?.scores, World.scores(version, [4, 2, 1, 1]), "original scores preserved")
        XCTAssertFalse(model.ranked(scope: .version(systemID: system.id, versionID: version.id)).contains { $0.restaurantID == ref.id })
        XCTAssertTrue(model.ranked(scope: .version(systemID: StarterSystems.fastCasual, versionID: fastCasual.id)).contains { $0.restaurantID == ref.id })

        // The client refuses an invalid rating before it reaches the backend.
        await assertThrows(try await model.saveVisit(
            existing: rerated, place: place, details: details,
            rating: RatingInput(versionID: fastCasual.id, scores: [fastCasual.criteria[0].id: 9], complete: false)))

        // Deleting the visit removes it everywhere.
        try await model.deleteVisit(rerated)
        XCTAssertFalse(model.visitedRestaurantIDs.contains(ref.id))
    }

    func testSeededDemoShowsTiesDraftsAndHistory() async throws {
        let model = AppModel(environment: .ephemeralDemo())
        try await model.signInDemo()

        let all = model.ranked(scope: .allSystems)
        XCTAssertEqual(all.count, 6)
        XCTAssertEqual(all.map(\.total), [9, 9, 9, 8, 8, 4])
        XCTAssertEqual(all.map(\.rank), [1, 1, 1, 4, 4, 6])
        XCTAssertEqual(model.draftVisits.count, 1)
        XCTAssertTrue(model.visits.contains { !$0.supersededRevisions.isEmpty })
        XCTAssertEqual(model.saved.count, 4)

        // Account deletion clears everything the user owned.
        try await model.deleteAccount()
        XCTAssertEqual(model.phase, .signedOut)
        XCTAssertTrue(model.visits.isEmpty)
        let state = try XCTUnwrap(model.environment.demoBackend).state
        XCTAssertFalse(state.visits.contains { $0.userID == DemoSeed.meID })
        XCTAssertFalse(state.users.contains { $0.id == DemoSeed.meID })
        XCTAssertFalse(state.follows.contains { $0.followerID == DemoSeed.meID || $0.followeeID == DemoSeed.meID })
    }
}
