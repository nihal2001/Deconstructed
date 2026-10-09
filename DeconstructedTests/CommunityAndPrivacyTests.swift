import XCTest
@testable import Deconstructed

@MainActor
final class CommunityAndPrivacyTests: XCTestCase {
    private func community(_ world: World) async throws -> [CommunityScore] {
        try await world.backend.communityScores(provider: "demo", placeID: "demo-test")
    }

    func testEachUserCountsOnceThroughTheirLatestVisit() async throws {
        let world = try await World()
        // Person 1 is a regular with three visits; only the latest (4/10) should count.
        try await world.rate(as: World.person(1), world.general, [5, 2, 2, 1], daysAgo: 60)
        try await world.rate(as: World.person(1), world.general, [5, 2, 2, 1], daysAgo: 30)
        try await world.rate(as: World.person(1), world.general, [2, 1, 1, 0], daysAgo: 2)
        try await world.rate(as: World.person(2), world.general, [4, 2, 1, 1], daysAgo: 5) // 8

        let scores = try await community(world)
        XCTAssertEqual(scores.count, 1)
        XCTAssertEqual(scores[0].userCount, 2)
        XCTAssertEqual(scores[0].average, 6.0, accuracy: 0.0001, "(4 + 8) / 2, not dominated by the frequent visitor")
        XCTAssertEqual(scores[0].formattedAverage, "6.0")
        let food = scores[0].criterionAverages.first { $0.criterion.name == "Food" }
        XCTAssertEqual(food?.average ?? 0, 3.0, accuracy: 0.0001)
    }

    func testSystemsAndVersionsAreNeverMixed() async throws {
        let world = try await World()
        try await world.rate(as: World.person(1), world.general, [5, 2, 2, 1])   // 10
        try await world.rate(as: World.person(2), world.general, [3, 2, 2, 1])   // 8
        try await world.rate(as: World.person(3), world.fastCasual, [1, 1, 0])   // 2
        try await world.rate(as: World.person(4), world.fineDining, [4, 3, 2, 1]) // 10

        let scores = try await community(world)
        XCTAssertEqual(Set(scores.map(\.systemName)), ["General", "Fine Dining", "Fast Casual"])
        let general = try XCTUnwrap(scores.first { $0.systemID == StarterSystems.general })
        XCTAssertEqual(general.userCount, 2)
        XCTAssertEqual(general.average, 9.0, accuracy: 0.0001, "the Fast Casual 2 must not drag General down")
        XCTAssertEqual(general.versionNumber, 1)
        XCTAssertEqual(Set(scores.map(\.versionID)).count, 3)
        // Criterion averages only ever refer to that version's own criteria.
        for score in scores {
            let version = world.version(score.systemID)
            XCTAssertEqual(score.criterionAverages.map(\.criterion.id), version.criteria.map(\.id))
        }
    }

    func testAnEditedTemplateBecomesCustomAndLeavesTheStandardAverage() async throws {
        let world = try await World()
        try await world.rate(as: World.person(1), world.general, [4, 2, 2, 1]) // 9, standard

        // Person 2 edits General (Food 6, Service 2, Value 1, Atmosphere 1) and rates with the copy.
        world.backend.impersonate(World.person(2))
        var draft = SystemDraft(name: "General", summary: "Mine", criteria: world.general.criteria)
        draft.criteria[0].setMaxPoints(6)
        draft.criteria[0].levels[6].detail = "Perfect"
        draft.criteria[0].needsLevelReview = false
        draft.criteria[2].setMaxPoints(1)
        draft.criteria[2].needsLevelReview = false
        let (fork, custom) = try await world.publishNew(draft, forkedFrom: StarterSystems.general)
        XCTAssertNotEqual(custom.systemID, StarterSystems.general)
        XCTAssertEqual(fork.ownerID, World.person(2))
        XCTAssertEqual(fork.forkedFromSystemID, StarterSystems.general)
        world.backend.impersonate(world.me)
        try await world.rate(as: World.person(2), custom, [1, 0, 0, 0]) // 1, custom

        let scores = try await community(world)
        XCTAssertEqual(scores.count, 1, "custom systems are not community buckets")
        XCTAssertEqual(scores[0].systemID, StarterSystems.general)
        XCTAssertEqual(scores[0].userCount, 1)
        XCTAssertEqual(scores[0].average, 9.0, accuracy: 0.0001)

        // The standard definition itself is untouched by the edit.
        let catalog = try await world.backend.loadCatalog()
        XCTAssertEqual(catalog.versions.first { $0.id == world.general.id }?.criteria, world.general.criteria)
    }

    func testOnlyPublicReviewsCountAndSmallSamplesAreLabelled() async throws {
        let world = try await World()
        try await world.rate(as: World.person(1), world.general, [5, 2, 2, 1], visibility: .everyone)
        try await world.rate(as: World.person(2), world.general, [0, 0, 0, 0], visibility: .onlyMe)
        try await world.rate(as: World.person(3), world.general, [0, 0, 0, 0], visibility: .followers)
        try await world.rate(as: World.person(4), world.general, [0, 0], visibility: .everyone, complete: false)

        var scores = try await community(world)
        XCTAssertEqual(scores[0].userCount, 1)
        XCTAssertEqual(scores[0].average, 10, accuracy: 0.0001)
        XCTAssertTrue(scores[0].isLimited, "fewer than five people is labelled Limited ratings")

        for person in 5...7 {
            try await world.rate(as: World.person(person), world.general, [5, 2, 2, 1])
        }
        scores = try await community(world)
        XCTAssertEqual(scores[0].userCount, 4)
        XCTAssertTrue(scores[0].isLimited)

        try await world.rate(as: World.person(8), world.general, [5, 2, 2, 1])
        scores = try await community(world)
        XCTAssertEqual(scores[0].userCount, 5)
        XCTAssertFalse(scores[0].isLimited)
    }

    func testPrivateReviewsCannotBeReadByOthers() async throws {
        let world = try await World()
        let author = World.person(1)
        let privateVisit = try await world.rate(as: author, world.general, [5, 2, 2, 1], visibility: .onlyMe)
        let followersVisit = try await world.rate(as: author, world.general, [4, 2, 2, 1], daysAgo: 2, visibility: .followers)
        let publicVisit = try await world.rate(as: author, world.general, [3, 2, 2, 1], daysAgo: 3, visibility: .everyone)
        let draftVisit = try await world.rate(as: author, world.general, [3], daysAgo: 4, visibility: .everyone, complete: false)

        // A stranger sees only the public review.
        var visible = try await world.backend.loadVisits(ofUser: author)
        XCTAssertEqual(visible.map(\.id), [publicVisit.id])
        var feed = try await world.backend.loadFeed()
        XCTAssertTrue(feed.isEmpty)

        // A follower also sees the followers-only review, but never the private one or the draft.
        try await world.follow(world.me, author)
        visible = try await world.backend.loadVisits(ofUser: author)
        XCTAssertEqual(Set(visible.map(\.id)), [publicVisit.id, followersVisit.id])
        feed = try await world.backend.loadFeed()
        XCTAssertEqual(Set(feed.map(\.id)), [publicVisit.id, followersVisit.id])
        XCTAssertFalse(feed.contains { $0.id == privateVisit.id || $0.id == draftVisit.id })

        // Following does not grant write access.
        await assertThrows(try await world.backend.deleteVisit(id: publicVisit.id))
        await assertThrows(try await world.backend.updateVisit(id: publicVisit.id, details: VisitDetails()))
        await assertThrows(try await world.backend.saveRating(
            visitID: publicVisit.id, versionID: world.general.id,
            scores: World.scores(world.general, [0, 0, 0, 0]), complete: true))

        // Removing the follower closes the followers-only review again.
        world.backend.impersonate(author)
        try await world.backend.removeFollower(userID: world.me)
        world.backend.impersonate(world.me)
        visible = try await world.backend.loadVisits(ofUser: author)
        XCTAssertEqual(visible.map(\.id), [publicVisit.id])

        // The author still sees everything of their own.
        world.backend.impersonate(author)
        let own = try await world.backend.loadMyVisits()
        XCTAssertEqual(own.count, 4)
    }

    func testVisibilityRuleMatrix() {
        let author = World.person(1)
        func visit(_ visibility: Visibility, completed: Bool) -> Visit {
            let id = UUID()
            let revision = RatingRevision(id: UUID(), visitID: id, systemID: StarterSystems.general, versionID: UUID(),
                                          scores: [:], state: completed ? .active : .draft, createdAt: .now,
                                          completedAt: completed ? .now : nil, total: completed ? 5 : nil)
            return Visit(id: id, userID: author, restaurantID: UUID(), visitedOn: .now, visibility: visibility,
                         revisions: [revision], createdAt: .now, updatedAt: .now)
        }
        let stranger = World.person(2)
        XCTAssertTrue(VisibilityRules.canView(visit(.everyone, completed: true), viewerID: stranger, viewerFollowsAuthor: false))
        XCTAssertFalse(VisibilityRules.canView(visit(.followers, completed: true), viewerID: stranger, viewerFollowsAuthor: false))
        XCTAssertTrue(VisibilityRules.canView(visit(.followers, completed: true), viewerID: stranger, viewerFollowsAuthor: true))
        XCTAssertFalse(VisibilityRules.canView(visit(.onlyMe, completed: true), viewerID: stranger, viewerFollowsAuthor: true))
        XCTAssertFalse(VisibilityRules.canView(visit(.everyone, completed: false), viewerID: stranger, viewerFollowsAuthor: true))
        XCTAssertTrue(VisibilityRules.canView(visit(.everyone, completed: true), viewerID: nil, viewerFollowsAuthor: false))
        XCTAssertTrue(VisibilityRules.canView(visit(.onlyMe, completed: false), viewerID: author, viewerFollowsAuthor: false))
        XCTAssertFalse(VisibilityRules.countsTowardCommunity(visit(.followers, completed: true)))
        XCTAssertFalse(VisibilityRules.countsTowardCommunity(visit(.everyone, completed: false)))
        XCTAssertTrue(VisibilityRules.countsTowardCommunity(visit(.everyone, completed: true)))
    }

    func testCustomSystemDefinitionsAreOnlyReadableThroughVisibleReviews() async throws {
        let world = try await World()
        let author = World.person(1)
        world.backend.impersonate(author)
        let draft = SystemDraft(name: "Secret Scale", summary: "", criteria: world.fastCasual.criteria)
            .duplicated(named: "Secret Scale")
        let (system, version) = try await world.publishNew(draft)
        world.backend.impersonate(world.me)

        try await world.rate(as: author, version, [5, 3, 2], visibility: .onlyMe)
        var readable = try await world.backend.loadDefinitions(versionIDs: [version.id])
        XCTAssertTrue(readable.versions.isEmpty, "a rubric used only on a private review stays private")

        try await world.rate(as: author, version, [5, 3, 2], daysAgo: 2, visibility: .everyone)
        readable = try await world.backend.loadDefinitions(versionIDs: [version.id])
        XCTAssertEqual(readable.versions.map(\.id), [version.id])
        XCTAssertNil(readable.systems.first?.draft)

        // It never appears in someone else's own catalogue, so it can't be picked for a rating.
        let mine = try await world.backend.loadCatalog()
        XCTAssertFalse(mine.systems.contains { $0.id == system.id })
        await assertThrows(try await world.rate(as: world.me, version, [5, 3, 2]))
    }
}
