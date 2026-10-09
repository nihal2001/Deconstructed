import XCTest
@testable import Deconstructed

@MainActor
final class RankingTests: XCTestCase {
    private func restaurants(_ world: World, _ count: Int) async throws -> [RestaurantRef] {
        var refs: [RestaurantRef] = []
        for index in 0..<count {
            refs.append(try await world.backend.ensureRestaurant(provider: "demo", placeID: "demo-r\(index)", coordinate: nil))
        }
        return refs
    }

    func testIncompleteRatingsDoNotAffectRankings() async throws {
        let world = try await World()
        let refs = try await restaurants(world, 2)
        try await world.rate(as: world.me, world.general, [4, 2, 2, 1], restaurant: refs[0])
        try await world.rate(as: world.me, world.general, [5, 2], restaurant: refs[1], complete: false)

        let visits = try await world.backend.loadMyVisits()
        let ranked = RankingEngine.rank(visits: visits, scope: .allSystems)
        XCTAssertEqual(ranked.map(\.restaurantID), [refs[0].id])
        XCTAssertEqual(RankingEngine.distribution(of: ranked).reduce(0, +), 1)
    }

    func testADraftReRatingLeavesTheSubmittedScoreInPlace() async throws {
        let world = try await World()
        let visit = try await world.rate(as: world.me, world.general, [4, 2, 2, 1])
        // Start re-rating with another system but don't finish.
        let updated = try await world.backend.saveRating(
            visitID: visit.id, versionID: world.fineDining.id,
            scores: [world.fineDining.criteria[0].id: 1], complete: false)

        XCTAssertEqual(updated.activeRevision?.total, 9)
        XCTAssertNotNil(updated.draftRevision)
        let ranked = RankingEngine.rank(visits: [updated], scope: .allSystems)
        XCTAssertEqual(ranked.first?.total, 9)
        XCTAssertEqual(ranked.first?.revision.systemID, StarterSystems.general)
    }

    func testEqualScoresStayTied() async throws {
        let world = try await World()
        let refs = try await restaurants(world, 5)
        let points: [[Int]] = [[5, 2, 2, 1], [4, 2, 1, 1], [3, 2, 2, 1], [4, 1, 2, 1], [1, 1, 1, 0]] // 10, 8, 8, 8, 3
        for (ref, score) in zip(refs, points) {
            try await world.rate(as: world.me, world.general, score, restaurant: ref)
        }
        let visits = try await world.backend.loadMyVisits()
        let names = Dictionary(uniqueKeysWithValues: zip(refs.map(\.id), ["Zed", "Mango", "Apple", "Kiwi", "Bean"]))
        let ranked = RankingEngine.rank(visits: visits, scope: .allSystems) { names[$0] ?? "" }

        XCTAssertEqual(ranked.map(\.total), [10, 8, 8, 8, 3])
        // Competition ranking: ties share a rank and the next rank skips.
        XCTAssertEqual(ranked.map(\.rank), [1, 2, 2, 2, 5])
        XCTAssertEqual(ranked.map(\.isTied), [false, true, true, true, false])
        // Within a tie the listing order is alphabetical and nothing else.
        XCTAssertEqual(ranked[1...3].map { names[$0.restaurantID] }, ["Apple", "Kiwi", "Mango"])

        // Changing the names reorders the tie but never the ranks.
        let renamed = RankingEngine.rank(visits: visits, scope: .allSystems) { _ in "Same" }
        XCTAssertEqual(renamed.map(\.rank), [1, 2, 2, 2, 5])
    }

    func testRankingUsesLatestCompletedVisitAndKeepsOlderOnes() async throws {
        let world = try await World()
        try await world.rate(as: world.me, world.general, [5, 2, 2, 1], daysAgo: 90)
        try await world.rate(as: world.me, world.general, [2, 1, 1, 0], daysAgo: 3)
        try await world.rate(as: world.me, world.general, [5, 2, 2, 1], daysAgo: 1, complete: false)

        let visits = try await world.backend.loadMyVisits()
        let ranked = RankingEngine.rank(visits: visits, scope: .allSystems)
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked[0].total, 4, "the most recent completed visit decides, not the best one")
        XCTAssertEqual(ranked[0].completedVisitCount, 2)
        XCTAssertEqual(visits.filter(\.isCompleted).compactMap(\.activeRevision?.total).sorted(), [4, 10], "earlier scores remain available")
    }

    func testEditingAVisitUpdatesRankings() async throws {
        let world = try await World()
        let refs = try await restaurants(world, 2)
        let first = try await world.rate(as: world.me, world.general, [3, 1, 1, 1], restaurant: refs[0]) // 6
        try await world.rate(as: world.me, world.general, [4, 2, 1, 1], restaurant: refs[1])             // 8

        var visits = try await world.backend.loadMyVisits()
        XCTAssertEqual(RankingEngine.rank(visits: visits, scope: .allSystems).map(\.restaurantID), [refs[1].id, refs[0].id])

        // Edit the first visit's scores upward.
        let edited = try await world.backend.saveRating(visitID: first.id, versionID: world.general.id,
                                                        scores: World.scores(world.general, [5, 2, 2, 1]), complete: true)
        XCTAssertEqual(edited.activeRevision?.total, 10)
        XCTAssertEqual(edited.supersededRevisions.map(\.total), [6], "the earlier rating is kept as history")

        visits = try await world.backend.loadMyVisits()
        let ranked = RankingEngine.rank(visits: visits, scope: .allSystems)
        XCTAssertEqual(ranked.map(\.restaurantID), [refs[0].id, refs[1].id])
        XCTAssertEqual(ranked.map(\.total), [10, 8])

        // Deleting it removes it from rankings.
        try await world.backend.deleteVisit(id: first.id)
        visits = try await world.backend.loadMyVisits()
        XCTAssertEqual(RankingEngine.rank(visits: visits, scope: .allSystems).map(\.restaurantID), [refs[1].id])
    }

    func testRankingsAreScopedToOneSystemAndVersion() async throws {
        let world = try await World()
        let refs = try await restaurants(world, 3)
        try await world.rate(as: world.me, world.general, [4, 2, 2, 1], restaurant: refs[0])
        try await world.rate(as: world.me, world.fastCasual, [5, 3, 2], restaurant: refs[1])
        // Same restaurant under two systems on different days.
        try await world.rate(as: world.me, world.general, [3, 1, 1, 1], daysAgo: 20, restaurant: refs[2])
        try await world.rate(as: world.me, world.fineDining, [4, 3, 2, 1], daysAgo: 2, restaurant: refs[2])

        let visits = try await world.backend.loadMyVisits()
        let general = RankingEngine.rank(visits: visits, scope: .version(systemID: StarterSystems.general, versionID: world.general.id))
        XCTAssertEqual(general.map(\.restaurantID), [refs[0].id, refs[2].id])
        XCTAssertEqual(general.map(\.total), [9, 6], "within a system, the latest visit rated with that system counts")
        XCTAssertTrue(general.allSatisfy { $0.revision.versionID == world.general.id })

        let all = RankingEngine.rank(visits: visits, scope: .allSystems)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.first { $0.restaurantID == refs[2].id }?.revision.systemID, StarterSystems.fineDining)
    }
}
