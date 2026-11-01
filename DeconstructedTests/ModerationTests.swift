import XCTest
@testable import Deconstructed

@MainActor
final class ModerationTests: XCTestCase {
    private func sharedVisit(_ world: World, author: UUID, notes: String = "Fine") async throws -> Visit {
        let visit = try await world.rate(as: author, world.general, [3, 1, 1, 1])
        world.backend.impersonate(author)
        defer { world.backend.impersonate(world.me) }
        var details = VisitDetails()
        details.visitedOn = visit.visitedOn
        details.visibility = .everyone
        details.notes = notes
        details.dishes = ["Soup"]
        _ = try await world.backend.updateVisit(id: visit.id, details: details)
        return try await world.backend.addPhoto(visitID: visit.id, jpeg: Data([1]))
    }

    // MARK: Blocking

    func testBlockingHidesBothPeopleAndEndsFollows() async throws {
        let world = try await World()
        let other = World.person(1)
        let review = try await sharedVisit(world, author: other)
        try await world.follow(world.me, other)
        try await world.follow(other, world.me)
        let mine = try await world.rate(as: world.me, world.general, [4, 2, 2, 1])

        try await world.backend.setBlocked(userID: other, blocked: true)

        var visible = try await world.backend.loadVisits(ofUser: other)
        XCTAssertTrue(visible.isEmpty)
        var feed = try await world.backend.loadFeed()
        XCTAssertTrue(feed.isEmpty)
        var found = try await world.backend.searchUsers("person1")
        XCTAssertTrue(found.isEmpty)
        var following = try await world.backend.loadFollowing()
        XCTAssertTrue(following.isEmpty)
        var followers = try await world.backend.loadFollowers()
        XCTAssertTrue(followers.isEmpty)
        await assertThrows(try await world.backend.setFollowing(userID: other, following: true))
        let blockedList = try await world.backend.loadBlockedUsers()
        XCTAssertEqual(blockedList.map(\.id), [other])

        // The other side is hidden in just the same way, and sees no sign of the block.
        world.backend.impersonate(other)
        visible = try await world.backend.loadVisits(ofUser: world.me)
        XCTAssertFalse(visible.contains { $0.id == mine.id })
        found = try await world.backend.searchUsers("me")
        XCTAssertFalse(found.contains { $0.id == world.me })
        await assertThrows(try await world.backend.setFollowing(userID: world.me, following: true))
        let theirBlocks = try await world.backend.loadBlockedUsers()
        XCTAssertTrue(theirBlocks.isEmpty)

        // Unblocking restores what each can see, but not the follows.
        world.backend.impersonate(world.me)
        try await world.backend.setBlocked(userID: other, blocked: false)
        visible = try await world.backend.loadVisits(ofUser: other)
        XCTAssertEqual(visible.map(\.id), [review.id])
        following = try await world.backend.loadFollowing()
        XCTAssertTrue(following.isEmpty)
        followers = try await world.backend.loadFollowers()
        XCTAssertTrue(followers.isEmpty)
        feed = try await world.backend.loadFeed()
        XCTAssertTrue(feed.isEmpty)
    }

    func testCommunityScoresIgnoreBlocksButNotBans() async throws {
        let world = try await World()
        let other = World.person(1)
        try await world.rate(as: other, world.general, [5, 2, 2, 1])
        try await world.backend.setBlocked(userID: other, blocked: true)
        var scores = try await world.backend.communityScores(provider: "demo", placeID: "demo-test")
        XCTAssertEqual(scores.first?.userCount, 1, "an anonymous average reveals no one")
        try await world.backend.setBlocked(userID: other, blocked: false)

        try await world.backend.report(.user(other), reason: .spam, details: "")
        let reports = try await world.backend.loadOpenReports()
        let report = try XCTUnwrap(reports.first)
        try await world.backend.moderate(reportID: report.id, action: .ban)
        scores = try await world.backend.communityScores(provider: "demo", placeID: "demo-test")
        XCTAssertTrue(scores.isEmpty)
    }

    // MARK: Reporting

    func testReportsKeepASnapshotAndRepeatsAddNothing() async throws {
        let world = try await World()
        let other = World.person(1)
        let review = try await sharedVisit(world, author: other, notes: "Reported words")

        try await world.backend.report(.visit(review.id), reason: .harassment, details: "  Mean  ")
        try await world.backend.report(.visit(review.id), reason: .harassment, details: "Again")
        var open = try await world.backend.loadOpenReports()
        XCTAssertEqual(open.count, 1)
        XCTAssertEqual(open[0].details, "Mean")
        XCTAssertEqual(open[0].reportedUserID, other)
        XCTAssertEqual(open[0].snapshot.notes, "Reported words")
        XCTAssertEqual(open[0].snapshot.dishes, ["Soup"])
        XCTAssertEqual(open[0].snapshot.username, "person1")
        XCTAssertEqual(open[0].snapshot.systemName, "General")
        XCTAssertEqual(open[0].snapshot.photoPaths.count, 1)

        // Deleting the review afterwards doesn't remove the evidence.
        world.backend.impersonate(other)
        try await world.backend.deleteVisit(id: review.id)
        world.backend.impersonate(world.me)
        open = try await world.backend.loadOpenReports()
        XCTAssertEqual(open.first?.snapshot.notes, "Reported words")
    }

    func testOnlyVisibleContentOfOthersCanBeReported() async throws {
        let world = try await World()
        let other = World.person(1)
        let hidden = try await world.rate(as: other, world.general, [3, 1, 1, 1], visibility: .onlyMe)
        let mine = try await world.rate(as: world.me, world.general, [3, 1, 1, 1])

        await assertThrows(try await world.backend.report(.visit(hidden.id), reason: .spam, details: ""))
        await assertThrows(try await world.backend.report(.visit(mine.id), reason: .spam, details: ""))
        await assertThrows(try await world.backend.report(.user(world.me), reason: .spam, details: ""))
        await assertThrows(try await world.backend.report(.user(UUID()), reason: .spam, details: ""))
        let open = try await world.backend.loadOpenReports()
        XCTAssertTrue(open.isEmpty)
    }

    // MARK: Moderation

    func testRemovingAReviewOrPhotoTakesItAwayForEveryone() async throws {
        let world = try await World()
        let other = World.person(1)
        let first = try await sharedVisit(world, author: other)
        let second = try await world.rate(as: other, world.general, [2, 1, 1, 1], daysAgo: 3)

        try await world.backend.report(.visit(second.id), reason: .spam, details: "")
        try await world.backend.report(.photo(try XCTUnwrap(first.photos.first).id), reason: .sexual, details: "")
        let open = try await world.backend.loadOpenReports()
        for report in open { try await world.backend.moderate(reportID: report.id, action: .removeContent) }

        let visible = try await world.backend.loadVisits(ofUser: other)
        XCTAssertEqual(visible.map(\.id), [first.id])
        XCTAssertEqual(visible.first?.photos, [])
        let remaining = try await world.backend.loadOpenReports()
        XCTAssertTrue(remaining.isEmpty)
        await assertThrows(try await world.backend.moderate(reportID: open[0].id, action: .dismiss))
    }

    func testResettingNamesAndDismissing() async throws {
        let world = try await World()
        let other = World.person(1)
        try await world.backend.report(.user(other), reason: .hate, details: "")
        try await world.backend.report(.user(World.person(2)), reason: .other, details: "")
        let open = try await world.backend.loadOpenReports()

        try await world.backend.moderate(reportID: open[0].id, action: .removeContent)
        let renamed = try await world.backend.searchUsers("new member")
        XCTAssertEqual(renamed.map(\.id), [other])

        try await world.backend.moderate(reportID: open[1].id, action: .dismiss)
        let stillThere = try await world.backend.searchUsers("person2")
        XCTAssertEqual(stillThere.map(\.id), [World.person(2)])
    }

    func testBanningHidesThePersonAndClosesTheirReports() async throws {
        let world = try await World()
        let other = World.person(1)
        let review = try await sharedVisit(world, author: other)
        try await world.follow(world.me, other)
        try await world.backend.report(.visit(review.id), reason: .spam, details: "")
        try await world.backend.report(.user(other), reason: .spam, details: "")

        let open = try await world.backend.loadOpenReports()
        try await world.backend.moderate(reportID: open[0].id, action: .ban)

        let remaining = try await world.backend.loadOpenReports()
        XCTAssertTrue(remaining.isEmpty, "a ban settles every report against that person")
        let visible = try await world.backend.loadVisits(ofUser: other)
        XCTAssertTrue(visible.isEmpty)
        let found = try await world.backend.searchUsers("person1")
        XCTAssertTrue(found.isEmpty)
        let following = try await world.backend.loadFollowing()
        XCTAssertTrue(following.isEmpty)
    }

    func testDeletingAnAccountRemovesEverything() async throws {
        let world = try await World()
        let other = World.person(1)
        _ = try await sharedVisit(world, author: other)
        try await world.backend.report(.user(other), reason: .spam, details: "")
        let reports = try await world.backend.loadOpenReports()
        let report = try XCTUnwrap(reports.first)

        try await world.backend.moderate(reportID: report.id, action: .deleteAccount)

        XCTAssertFalse(world.backend.state.users.contains { $0.id == other })
        XCTAssertFalse(world.backend.state.visits.contains { $0.userID == other })
    }

    // MARK: Text filter

    func testFilterCatchesDisguisesButNotOrdinaryWords() {
        XCTAssertFalse(ContentFilter.allows("K1LL   y0urs3lf!!"))
        XCTAssertFalse(ContentFilter.allows("kill_yourself"))
        XCTAssertFalse(ContentFilter.allows("killl yourself"))
        XCTAssertFalse(ContentFilter.allows("kiiill yourselfff"))
        XCTAssertFalse(ContentFilter.allows("killl yourselfff"))
        XCTAssertTrue(ContentFilter.allows("Skillful cooking, and the pasta was shit"))
        XCTAssertTrue(ContentFilter.allows(""))
    }

    func testFilteredTextIsRefusedEverywhereItCanBeWritten() async throws {
        let world = try await World()
        var details = VisitDetails()
        details.notes = "kill yourself"
        await assertThrows(try await world.backend.createVisit(restaurantID: world.restaurant.id, details: details))
        details.notes = ""
        details.dishes = ["go die"]
        await assertThrows(try await world.backend.createVisit(restaurantID: world.restaurant.id, details: details))

        var profile = try XCTUnwrap(world.backend.state.users.first { $0.id == world.me })
        profile.displayName = "kill yourself"
        await assertThrows(try await world.backend.updateProfile(profile))
        profile.displayName = "Me"
        profile.username = "kill_yourself"
        await assertThrows(try await world.backend.updateProfile(profile))

        let draft = SystemDraft(name: "kys", summary: "", criteria: world.fastCasual.criteria)
        await assertThrows(try await world.backend.saveDraft(systemID: nil, draft: draft, forkedFrom: nil))
    }

    // MARK: Terms

    func testNothingCanBePostedBeforeAcceptingTheTerms() async throws {
        let model = AppModel(environment: .ephemeralDemo())
        try await model.signInDemo()
        XCTAssertFalse(model.hasAcceptedTerms)
        let backend = try XCTUnwrap(model.environment.demoBackend)
        let restaurant = try await backend.ensureRestaurant(provider: "demo", placeID: "demo-terms", coordinate: nil)
        await assertThrows(try await backend.createVisit(restaurantID: restaurant.id, details: VisitDetails()))

        try await model.acceptTerms()
        XCTAssertTrue(model.hasAcceptedTerms)
        _ = try await backend.createVisit(restaurantID: restaurant.id, details: VisitDetails())

        // The date can't be forged or cleared through a profile update.
        var profile = try XCTUnwrap(model.profile)
        let accepted = profile.termsAcceptedAt
        profile.termsAcceptedAt = nil
        let saved = try await backend.updateProfile(profile)
        XCTAssertEqual(saved.termsAcceptedAt, accepted)
    }
}
