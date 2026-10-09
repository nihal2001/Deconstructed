import XCTest
@testable import Deconstructed

@MainActor
final class ScoringTests: XCTestCase {
    func testStarterSystemsAreValidAndTotalTen() {
        let catalog = StarterSystems.catalog
        XCTAssertEqual(catalog.systems.map(\.name), ["General", "Fine Dining", "Fast Casual"])
        let expected: [String: [String: Int]] = [
            "General": ["Food": 5, "Service": 2, "Value": 2, "Atmosphere": 1],
            "Fine Dining": ["Food": 4, "Service": 3, "Atmosphere": 2, "Value": 1],
            "Fast Casual": ["Food": 5, "Value": 3, "Speed and Accuracy": 2],
        ]
        for system in catalog.systems {
            let version = catalog.versions.first { $0.id == system.currentVersionID }!
            XCTAssertEqual(version.criteria.reduce(0) { $0 + $1.maxPoints }, 10, system.name)
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: version.criteria.map { ($0.name, $0.maxPoints) }), expected[system.name])
            let draft = SystemDraft(name: system.name, summary: system.summary, criteria: version.criteria)
            XCTAssertEqual(SystemValidator.issues(for: draft), [], system.name)
            for criterion in version.criteria {
                XCTAssertEqual(criterion.levels.map(\.points), Array(0...criterion.maxPoints))
                XCTAssertTrue(criterion.levels.allSatisfy { !$0.detail.isBlank && !$0.label.isBlank })
            }
        }
    }

    /// Every valid combination of criterion scores, for every starter system, sums correctly.
    func testEveryValidCombinationProducesTheCorrectTotal() {
        var checked = 0
        for version in StarterSystems.catalog.versions {
            for combination in Self.combinations(version.criteria.map(\.maxPoints)) {
                let scores = World.scores(version, combination)
                XCTAssertEqual(RatingEngine.issues(scores: scores, version: version, requireComplete: true), [])
                XCTAssertEqual(RatingEngine.completedTotal(scores: scores, version: version), combination.reduce(0, +))
                XCTAssertTrue((0...10).contains(combination.reduce(0, +)))
                checked += 1
            }
        }
        // General 6·3·3·2, Fine Dining 5·4·3·2, Fast Casual 6·4·3
        XCTAssertEqual(checked, 108 + 120 + 72)
    }

    /// The same check through the backend path, which computes the stored total itself.
    func testBackendDerivesTotalForEveryCombination() async throws {
        let world = try await World()
        let version = world.fastCasual
        let visit = try await world.backend.createVisit(restaurantID: world.restaurant.id, details: VisitDetails())
        for combination in Self.combinations(version.criteria.map(\.maxPoints)) {
            let saved = try await world.backend.saveRating(visitID: visit.id, versionID: version.id,
                                                           scores: World.scores(version, combination), complete: true)
            XCTAssertEqual(saved.activeRevision?.total, combination.reduce(0, +))
        }
    }

    func testOutOfRangeAndUnknownScoresAreRejected() async throws {
        let world = try await World()
        let version = world.general
        let visit = try await world.backend.createVisit(restaurantID: world.restaurant.id, details: VisitDetails())

        var tooHigh = World.scores(version, [5, 2, 2, 1])
        tooHigh[version.criteria[0].id] = 6
        var negative = World.scores(version, [5, 2, 2, 1])
        negative[version.criteria[3].id] = -1
        var foreign = World.scores(version, [5, 2, 2, 1])
        foreign[world.fastCasual.criteria[0].id] = 1

        for scores in [tooHigh, negative, foreign] {
            XCTAssertFalse(RatingEngine.issues(scores: scores, version: version, requireComplete: true).isEmpty)
            await assertThrows(try await world.backend.saveRating(visitID: visit.id, versionID: version.id, scores: scores, complete: true))
            // Drafts may be incomplete but never invalid.
            await assertThrows(try await world.backend.saveRating(visitID: visit.id, versionID: version.id, scores: scores, complete: false))
        }
        let stored = try await world.backend.loadMyVisits()
        XCTAssertTrue(stored.allSatisfy { $0.revisions.isEmpty })
    }

    func testAllCriteriaMustBeAnsweredBeforeSubmission() async throws {
        let world = try await World()
        let version = world.general
        let visit = try await world.backend.createVisit(restaurantID: world.restaurant.id, details: VisitDetails())
        var partial = World.scores(version, [4, 2, 2, 1])
        partial[version.criteria[2].id] = nil

        XCTAssertNil(RatingEngine.completedTotal(scores: partial, version: version))
        XCTAssertEqual(RatingEngine.runningTotal(scores: partial, version: version), 7)
        await assertThrows(try await world.backend.saveRating(visitID: visit.id, versionID: version.id, scores: partial, complete: true))

        let draft = try await world.backend.saveRating(visitID: visit.id, versionID: version.id, scores: partial, complete: false)
        XCTAssertFalse(draft.isCompleted)
        XCTAssertNil(draft.draftRevision?.total)
    }

    func testAZeroScoreIsAnAnswerNotAGap() {
        let version = StarterSystems.catalog.versions[0]
        let scores = World.scores(version, [0, 0, 0, 0])
        XCTAssertTrue(RatingEngine.isComplete(scores: scores, version: version))
        XCTAssertEqual(RatingEngine.completedTotal(scores: scores, version: version), 0)
    }

    static func combinations(_ maxima: [Int]) -> [[Int]] {
        maxima.reduce([[]]) { partial, maximum in
            partial.flatMap { prefix in (0...maximum).map { prefix + [$0] } }
        }
    }
}
