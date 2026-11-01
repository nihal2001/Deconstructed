import XCTest
@testable import Deconstructed

/// Answers any place ID, so a test can ask for as many names as it likes.
@MainActor
private final class AnyPlaceProvider: PlacesProvider {
    let providerKey = "demo"
    let isDemo = true
    private(set) var detailRequests = 0

    func autocomplete(query: String, near: Coordinate?, session: PlacesSession) async throws -> [PlaceSuggestion] { [] }
    func searchText(_ query: String, near: Coordinate?) async throws -> [Place] { [] }
    func searchArea(_ bounds: GeoBounds) async throws -> [Place] { [] }

    func details(placeID: String, level: PlaceDetailLevel, session: PlacesSession?) async throws -> Place {
        detailRequests += 1
        return Place(placeID: placeID, level: level, name: "Name of \(placeID)")
    }
}

@MainActor
final class LaunchAndLimitTests: XCTestCase {
    // MARK: Launch without a connection

    private func signedInModel() async throws -> AppModel {
        let model = AppModel(environment: .ephemeralDemo())
        try await model.signInDemo()
        return model
    }

    func testLaunchingOfflineKeepsPeopleSignedInAndRecovers() async throws {
        let model = try await signedInModel()
        model.environment.demoControls.simulateOffline = true

        await model.bootstrap()
        XCTAssertEqual(model.phase, .unavailable, "a failed load is not a sign-out")
        XCTAssertNotNil(model.profile)

        model.environment.demoControls.simulateOffline = false
        await model.bootstrap()
        XCTAssertEqual(model.phase, .signedIn)
        XCTAssertFalse(model.visits.isEmpty)
    }

    func testARealSignOutStillShowsSignIn() async throws {
        let model = try await signedInModel()
        await model.signOut()
        await model.bootstrap()
        XCTAssertEqual(model.phase, .signedOut)
    }

    // MARK: Places limits

    private func model(perMinute: Int, perDay: Int = 1_000) -> (AppModel, AnyPlaceProvider, () -> Date, (TimeInterval) -> Void) {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let monitor = RequestMonitor(limits: .init(perMinute: perMinute, perDay: perDay), defaults: nil, now: { clock })
        let places = AnyPlaceProvider()
        let base = AppEnvironment.ephemeralDemo()
        let environment = AppEnvironment(
            config: AppConfig(), backend: base.backend,
            places: MeteredPlacesProvider(base: places, monitor: monitor),
            monitor: monitor, demoControls: base.demoControls, demoBackend: base.demoBackend)
        return (AppModel(environment: environment), places, { clock }, { clock.addTimeInterval($0) })
    }

    func testAListLongerThanTheMinuteLimitStillGetsEveryName() async {
        let (model, places, _, advance) = model(perMinute: 30)
        var waits = 0
        model.waitForPlaceLimit = { seconds in
            waits += 1
            advance(seconds)
        }

        for number in 1...50 {
            await model.ensurePlace("place-\(number)")
        }

        XCTAssertEqual(places.detailRequests, 50)
        XCTAssertEqual(waits, 1)
        XCTAssertNil(model.placeLoadError, "waiting for the limit isn't an error")
        XCTAssertEqual(model.places.count, 50)
    }

    func testTheDailyLimitIsReportedRatherThanWaitedOut() async {
        let (model, _, _, _) = model(perMinute: 1_000, perDay: 2)
        model.waitForPlaceLimit = { _ in XCTFail("the daily limit shouldn't be waited out") }

        for number in 1...3 {
            await model.ensurePlace("place-\(number)")
        }

        guard case .localLimitReached? = model.placeLoadError else { return XCTFail("expected the daily limit") }
    }

    // MARK: Developer text

    func testErrorsDontContainSetupAdvice() {
        let shown = [PlacesError.notConfigured.errorDescription, PlacesError.other(PlacesError.unavailableMessage).errorDescription]
        for message in shown.compactMap({ $0 }) {
            for word in ["key", "API", "bundle", "xcconfig", "Google"] {
                XCTAssertFalse(message.contains(word), "\(message) mentions \(word)")
            }
        }
    }
}
