import XCTest
@testable import Deconstructed

@MainActor
final class RankingSystemTests: XCTestCase {
    private func validDraft(named name: String = "Ramen") -> SystemDraft {
        func criterion(_ name: String, _ max: Int) -> Criterion {
            Criterion(id: UUID(), name: name, guidance: "", maxPoints: max,
                      levels: (0...max).map { ScoreLevel(points: $0, label: "L\($0)", detail: "\(name) worth \($0)") })
        }
        return SystemDraft(name: name, summary: "Bowls", criteria: [criterion("Broth", 5), criterion("Noodles", 3), criterion("Toppings", 2)])
    }

    // MARK: Validation

    func testMaximumsMustTotalExactlyTen() {
        var draft = validDraft()
        XCTAssertTrue(SystemValidator.canActivate(draft))
        XCTAssertEqual(draft.allocatedPoints, 10)

        draft.criteria.removeLast()
        XCTAssertEqual(draft.allocatedPoints, 8)
        XCTAssertTrue(SystemValidator.issues(for: draft).contains(.allocation(allocated: 8)))
        XCTAssertEqual(SystemIssue.allocation(allocated: 8).message, "Allocate 2 more points so the criteria total 10.")

        draft = validDraft()
        draft.criteria[0].setMaxPoints(7)
        XCTAssertTrue(SystemValidator.issues(for: draft).contains(.allocation(allocated: 12)))
    }

    func testEveryScoreNeedsADescriptionAndCriteriaNeedDistinctNames() {
        var draft = validDraft()
        draft.criteria[1].levels[2].detail = "   "
        XCTAssertTrue(SystemValidator.issues(for: draft).contains {
            if case .missingDescriptions(_, "Noodles", [2]) = $0 { return true } else { return false }
        })

        draft = validDraft()
        draft.criteria[2].name = "broth"
        XCTAssertTrue(SystemValidator.issues(for: draft).contains(.duplicateCriterionName(name: "broth")))

        draft = validDraft()
        draft.name = " "
        XCTAssertTrue(SystemValidator.issues(for: draft).contains(.missingName))
        XCTAssertFalse(SystemValidator.canActivate(SystemDraft.blank))
    }

    func testChangingAMaximumRequiresReviewingItsDescriptions() {
        var draft = validDraft()
        draft.criteria[0].setMaxPoints(4) // 5 → 4, total now 9
        draft.criteria[2].setMaxPoints(3) // 2 → 3, total back to 10

        XCTAssertEqual(draft.criteria[0].levels.map(\.points), [0, 1, 2, 3, 4], "descriptions for surviving scores are kept")
        XCTAssertEqual(draft.criteria[0].levels[3].detail, "Broth worth 3")
        XCTAssertEqual(draft.criteria[2].levels.count, 4)
        XCTAssertTrue(draft.criteria[2].levels[3].detail.isEmpty, "the new score starts undescribed")

        let issues = SystemValidator.issues(for: draft)
        XCTAssertEqual(issues.filter { if case .needsReview = $0 { return true } else { return false } }.count, 2)
        XCTAssertFalse(SystemValidator.canActivate(draft))

        draft.criteria[2].levels[3].detail = "Loaded"
        draft.criteria[0].needsLevelReview = false
        XCTAssertFalse(SystemValidator.canActivate(draft), "one criterion is still awaiting review")
        draft.criteria[2].needsLevelReview = false
        XCTAssertTrue(SystemValidator.canActivate(draft))

        // Setting the same maximum again is not a change.
        var untouched = validDraft()
        untouched.criteria[0].setMaxPoints(5)
        XCTAssertFalse(untouched.criteria[0].needsLevelReview)
    }

    // MARK: Lifecycle

    func testNewSystemsStayDraftsUntilComplete() async throws {
        let world = try await World()
        var draft = validDraft()
        draft.criteria.removeLast()
        let system = try await world.backend.saveDraft(systemID: nil, draft: draft, forkedFrom: nil)
        XCTAssertTrue(system.isDraftOnly)
        XCTAssertFalse(system.isSelectableForNewRatings)
        XCTAssertEqual(system.draft, draft)

        await assertThrows(try await world.backend.publish(systemID: system.id, draft: draft), "8 of 10 points")
        let stillDraft = try await world.mySystem(system.id)
        XCTAssertEqual(stillDraft?.isDraftOnly, true)

        let complete = validDraft()
        let published = try await world.backend.publish(systemID: system.id, draft: complete)
        XCTAssertEqual(published.versions.map(\.number), [1])
        XCTAssertEqual(published.systems.first?.currentVersionID, published.versions.first?.id)
        XCTAssertNil(published.systems.first?.draft)
        XCTAssertEqual(published.systems.first?.isSelectableForNewRatings, true)
    }

    func testEditingCreatesANewVersionAndHistoryIsNotRecalculated() async throws {
        let world = try await World()
        let (system, v1) = try await world.publishNew(validDraft())
        let visit = try await world.rate(as: world.me, v1, [5, 3, 2]) // 10 under v1
        let before = try XCTUnwrap(visit.activeRevision)

        // Renaming alone does not create a version.
        var renamed = SystemDraft(name: "Noodle Soup", summary: "Bowls", criteria: v1.criteria)
        var catalog = try await world.backend.publish(systemID: system.id, draft: renamed)
        XCTAssertEqual(catalog.versions.count, 1)
        XCTAssertEqual(catalog.systems.first?.name, "Noodle Soup")

        // Reweighting does: Broth 5 → 4, Toppings 2 → 3.
        renamed.criteria[0].setMaxPoints(4)
        renamed.criteria[2].setMaxPoints(3)
        renamed.criteria[2].levels[3].detail = "Loaded"
        renamed.criteria[0].needsLevelReview = false
        renamed.criteria[2].needsLevelReview = false
        catalog = try await world.backend.publish(systemID: system.id, draft: renamed)
        XCTAssertEqual(catalog.versions.map(\.number).sorted(), [1, 2])
        let v2 = try XCTUnwrap(catalog.versions.first { $0.number == 2 })
        XCTAssertEqual(catalog.systems.first?.currentVersionID, v2.id)

        // Version 1 is byte-for-byte what it was, and so is the rating made with it.
        XCTAssertEqual(catalog.versions.first { $0.number == 1 }, v1)
        let reloaded = try await world.myVisit(visit.id)
        let after = try XCTUnwrap(reloaded?.activeRevision)
        XCTAssertEqual(after, before)
        XCTAssertEqual(after.versionID, v1.id)
        XCTAssertEqual(after.total, 10)
        // Each version owns its criteria, so old scores can't be read against new criteria.
        XCTAssertTrue(Set(v1.criteria.map(\.id)).isDisjoint(with: v2.criteria.map(\.id)))

        // New ratings must use the latest version…
        let other = try await world.backend.ensureRestaurant(provider: "demo", placeID: "demo-other", coordinate: nil)
        await assertThrows(try await world.rate(as: world.me, v1, [5, 3, 2], restaurant: other))
        try await world.rate(as: world.me, v2, [4, 3, 3], restaurant: other)

        // …but an existing rating may still be corrected under its own version…
        let corrected = try await world.backend.saveRating(visitID: visit.id, versionID: v1.id,
                                                           scores: World.scores(v1, [4, 3, 2]), complete: true)
        XCTAssertEqual(corrected.activeRevision?.total, 9)
        XCTAssertEqual(corrected.activeRevision?.versionID, v1.id)

        // …or explicitly re-rated with the new one, keeping the previous revisions as history.
        let rerated = try await world.backend.saveRating(visitID: visit.id, versionID: v2.id,
                                                         scores: World.scores(v2, [4, 3, 3]), complete: true)
        XCTAssertEqual(rerated.activeRevision?.versionID, v2.id)
        XCTAssertEqual(rerated.revisions.filter { $0.state == .active }.count, 1)
        XCTAssertEqual(rerated.supersededRevisions.map(\.total), [9, 10])
        XCTAssertEqual(rerated.supersededRevisions.map(\.versionID), [v1.id, v1.id])

        // Only the active revision counts in rankings.
        let ranked = RankingEngine.rank(visits: [rerated], scope: .allSystems)
        XCTAssertEqual(ranked.map(\.total), [10])
        XCTAssertEqual(ranked.first?.revision.versionID, v2.id)
        XCTAssertTrue(RankingEngine.rank(visits: [rerated], scope: .version(systemID: system.id, versionID: v1.id)).isEmpty)
    }

    func testResubmittingIdenticalScoresAddsNoHistory() async throws {
        let world = try await World()
        let visit = try await world.rate(as: world.me, world.general, [4, 2, 2, 1])
        let again = try await world.backend.saveRating(visitID: visit.id, versionID: world.general.id,
                                                       scores: World.scores(world.general, [4, 2, 2, 1]), complete: true)
        XCTAssertEqual(again.revisions.count, 1)
        XCTAssertEqual(again.activeRevision?.id, visit.activeRevision?.id)
    }

    func testArchivedSystemsStayReadableButCannotBeSelected() async throws {
        let world = try await World()
        let (system, version) = try await world.publishNew(validDraft())
        let visit = try await world.rate(as: world.me, version, [5, 3, 2])

        let archived = try await world.backend.setArchived(systemID: system.id, archived: true)
        XCTAssertTrue(archived.isArchived)
        XCTAssertFalse(archived.isSelectableForNewRatings)

        // Still in the catalogue with its definition, so the old rating renders in full.
        let catalog = try await world.backend.loadCatalog()
        XCTAssertNotNil(catalog.versions.first { $0.id == version.id })
        let reloaded = try await world.myVisit(visit.id)
        XCTAssertEqual(reloaded?.activeRevision?.total, 10)

        let other = try await world.backend.ensureRestaurant(provider: "demo", placeID: "demo-other", coordinate: nil)
        await assertThrows(try await world.rate(as: world.me, version, [5, 3, 2], restaurant: other))

        // A system with ratings can never be permanently deleted.
        let error = await assertThrows(try await world.backend.deleteSystem(systemID: system.id))
        XCTAssertNotNil(error as? BackendError)
        let kept = try await world.mySystem(system.id)
        XCTAssertNotNil(kept)

        // An unused one can.
        let unused = try await world.backend.saveDraft(systemID: nil, draft: validDraft(named: "Unused"), forkedFrom: nil)
        try await world.backend.deleteSystem(systemID: unused.id)
        let gone = try await world.mySystem(unused.id)
        XCTAssertNil(gone)
    }

    func testUsersCanOnlyEditSystemsTheyOwn() async throws {
        let world = try await World()
        let draft = validDraft()

        // Standard systems are read-only to everyone.
        await assertThrows(try await world.backend.saveDraft(systemID: StarterSystems.general, draft: draft, forkedFrom: nil))
        await assertThrows(try await world.backend.publish(systemID: StarterSystems.general, draft: draft))
        await assertThrows(try await world.backend.setArchived(systemID: StarterSystems.general, archived: true))
        await assertThrows(try await world.backend.deleteSystem(systemID: StarterSystems.general))

        // Someone else's custom system is off limits too.
        let mine = try await world.backend.saveDraft(systemID: nil, draft: draft, forkedFrom: nil)
        _ = try await world.backend.publish(systemID: mine.id, draft: draft)
        world.backend.impersonate(World.person(1))
        await assertThrows(try await world.backend.saveDraft(systemID: mine.id, draft: draft, forkedFrom: nil))
        await assertThrows(try await world.backend.publish(systemID: mine.id, draft: draft))
        await assertThrows(try await world.backend.setArchived(systemID: mine.id, archived: true))
        await assertThrows(try await world.backend.deleteSystem(systemID: mine.id))
        world.backend.impersonate(world.me)
        let untouched = try await world.mySystem(mine.id)
        XCTAssertEqual(untouched?.isArchived, false)
    }

    // MARK: Through the app model

    func testEditingAStarterCreatesAPersonalCopyAndSwitchesDefault() async throws {
        let model = AppModel(environment: .ephemeralDemo())
        try await model.signInDemo()
        let general = try XCTUnwrap(model.systems[StarterSystems.general])
        XCTAssertEqual(model.defaultSystem?.id, general.id)
        let standardVersion = try XCTUnwrap(model.currentVersion(of: general))

        var draft = general.editableDraft(currentVersion: standardVersion)
        draft.criteria[0].setMaxPoints(6)
        draft.criteria[0].levels[6].detail = "Transcendent"
        draft.criteria[0].needsLevelReview = false
        // 11 of 10: refused on the client before anything is sent.
        await assertThrows(try await model.publishSystem(draft, for: general))
        draft.criteria[1].setMaxPoints(1)
        draft.criteria[1].needsLevelReview = false

        let copy = try await model.publishSystem(draft, for: general)
        XCTAssertNotEqual(copy.id, general.id)
        XCTAssertEqual(copy.ownerID, DemoSeed.meID)
        XCTAssertEqual(copy.forkedFromSystemID, general.id)
        XCTAssertEqual(model.currentVersion(of: copy)?.number, 1)
        XCTAssertEqual(model.defaultSystem?.id, copy.id, "the default follows the user to their copy")
        XCTAssertFalse(model.selectableSystems.contains { $0.id == general.id }, "the standard one is put away")
        XCTAssertTrue(model.archivedSystems.contains { $0.id == general.id })

        // The shared definition did not change, and old ratings still point at it.
        XCTAssertEqual(model.version(general.currentVersionID), standardVersion)
        XCTAssertTrue(model.visits.contains { $0.activeRevision?.versionID == standardVersion.id })

        // The standard system can be restored alongside the copy.
        try await model.setArchived(general, archived: false)
        XCTAssertTrue(model.selectableSystems.contains { $0.id == general.id })
        XCTAssertTrue(model.selectableSystems.contains { $0.id == copy.id })
    }

    func testDuplicateStartsAsAnIndependentDraft() async throws {
        let model = AppModel(environment: .ephemeralDemo())
        try await model.signInDemo()
        let fastCasual = try XCTUnwrap(model.systems[StarterSystems.fastCasual])
        let copy = try await model.duplicateSystem(fastCasual)

        XCTAssertEqual(copy.name, "Fast Casual copy")
        XCTAssertTrue(copy.isDraftOnly)
        XCTAssertTrue(model.draftSystems.contains { $0.id == copy.id })
        XCTAssertFalse(model.selectableSystems.contains { $0.id == copy.id })
        let draft = try XCTUnwrap(copy.draft)
        XCTAssertTrue(SystemValidator.canActivate(draft))
        let originalIDs = Set(model.currentVersion(of: fastCasual)!.criteria.map(\.id))
        XCTAssertTrue(originalIDs.isDisjoint(with: draft.criteria.map(\.id)))

        let active = try await model.publishSystem(draft, for: copy)
        XCTAssertTrue(model.selectableSystems.contains { $0.id == active.id })
        XCTAssertFalse(active.isStandard)
    }
}
