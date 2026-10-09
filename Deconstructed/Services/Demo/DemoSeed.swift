import Foundation

struct DemoFollow: Codable, Hashable {
    var followerID: UUID
    var followeeID: UUID
}

struct DemoState: Codable {
    /// Bump when the shape or the seed changes so stale demo files are discarded.
    static let currentSchema = 3

    var schema = DemoState.currentSchema
    var signedInUserID: UUID?
    var users: [UserProfile] = []
    var systems: [RankingSystem] = []
    var versions: [SystemVersion] = []
    var restaurants: [RestaurantRef] = []
    var saved: [UUID: [SavedPlace]] = [:]
    var visits: [Visit] = []
    var follows: [DemoFollow] = []
}

/// Builds the fictional world the demo starts with: one "you", seven invented people, and
/// enough ratings to show ties, drafts, re-rated visits, custom systems and community scores.
enum DemoSeed {
    static let meID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    private static func userID(_ n: Int) -> UUID {
        UUID(uuidString: "22222222-2222-4222-8222-\(String(format: "%012d", n))")!
    }

    static func make(now: Date = .now) -> DemoState {
        var state = DemoState()
        var rng = SplitMix64(seed: 0xDEC0_4571)
        let starters = StarterSystems.catalog
        state.systems = starters.systems
        state.versions = starters.versions

        state.users = [
            UserProfile(id: meID, username: "you", displayName: "You", defaultVisibility: .followers,
                        defaultSystemID: StarterSystems.general),
            UserProfile(id: userID(1), username: "amara", displayName: "Amara Osei", defaultVisibility: .everyone),
            UserProfile(id: userID(2), username: "leoeats", displayName: "Leo Castellanos", defaultVisibility: .everyone),
            UserProfile(id: userID(3), username: "priya.n", displayName: "Priya Nair", defaultVisibility: .followers),
            UserProfile(id: userID(4), username: "mei", displayName: "Mei Tanaka", defaultVisibility: .everyone),
            UserProfile(id: userID(5), username: "jonasw", displayName: "Jonas Weber", defaultVisibility: .everyone),
            UserProfile(id: userID(6), username: "sofiar", displayName: "Sofia Rossi", defaultVisibility: .everyone),
            UserProfile(id: userID(7), username: "dan_o", displayName: "Daniel Okafor", defaultVisibility: .everyone),
        ]
        state.follows = [1, 2, 3, 4].map { DemoFollow(followerID: meID, followeeID: userID($0)) }
            + [1, 6].map { DemoFollow(followerID: userID($0), followeeID: meID) }

        state.restaurants = DemoCatalog.restaurants.enumerated().map { index, restaurant in
            RestaurantRef(id: UUID(uuidString: "33333333-3333-4333-8333-\(String(format: "%012d", index + 1))")!,
                          provider: DemoCatalog.providerKey, providerPlaceID: restaurant.placeID,
                          cachedCoordinate: restaurant.coordinate, coordinateCachedAt: now)
        }
        let refs = Dictionary(uniqueKeysWithValues: state.restaurants.map { ($0.providerPlaceID, $0) })
        let versions = Dictionary(uniqueKeysWithValues: state.versions.map { ($0.systemID, $0) })

        // Mei rates noodle places with her own rubric. It shows on her reviews but is never
        // part of a community average.
        let noodleSystemID = UUID(uuidString: "44444444-4444-4444-8444-000000000001")!
        let noodleVersion = SystemVersion(
            id: UUID(uuidString: "44444444-4444-4444-8444-000000000002")!, systemID: noodleSystemID, number: 1,
            criteria: [
                criterion("Broth", "Depth, balance and temperature.", ["Thin or off", "Flat", "Decent", "Rich and balanced", "Would drink the bowl"]),
                criterion("Noodles", "Texture and how well they hold up.", ["Mushy", "Soft", "Good chew", "Perfect bite to the last strand"]),
                criterion("Toppings", "Quality and proportion.", ["Skimpy or stale", "Fine", "Generous and well made"]),
                criterion("Vibe", "Counter, music, the whole feel.", ["Rushed", "Makes you want to linger"]),
            ],
            publishedAt: now.addingTimeInterval(-200 * 86_400))
        state.systems.append(RankingSystem(
            id: noodleSystemID, ownerID: userID(4), templateKey: nil, forkedFromSystemID: nil,
            name: "Noodle Scale", summary: "Mei's rubric for anything served in broth.",
            currentVersionID: noodleVersion.id, createdAt: noodleVersion.publishedAt, updatedAt: noodleVersion.publishedAt))
        state.versions.append(noodleVersion)

        // Other people's visits.
        for (restaurantIndex, restaurant) in DemoCatalog.restaurants.enumerated() {
            guard let ref = refs[restaurant.placeID] else { continue }
            for userNumber in 1...7 {
                // The first six restaurants are rated by everyone so they clear the
                // five-person threshold; the rest get a thinner, "Limited ratings" spread.
                let visits = restaurantIndex < 6 || (restaurantIndex + userNumber * 3) % 4 == 0
                guard visits else { continue }
                let author = state.users[userNumber]
                let usesNoodleScale = userNumber == 4 && restaurant.format == .noodles
                guard let version = usesNoodleScale ? noodleVersion : versions[restaurant.format.systemID] else { continue }

                var visibility = author.defaultVisibility
                if userNumber == 5, restaurantIndex % 3 == 0 { visibility = .onlyMe }
                if userNumber == 2, restaurantIndex % 5 == 0 { visibility = .followers }

                let daysAgo = Int.random(in: 2...150, using: &rng)
                let scores = seededScores(version: version, quality: restaurant.quality, rng: &rng)
                state.visits.append(completedVisit(
                    userID: author.id, restaurantID: ref.id, version: version, scores: scores,
                    visitedOn: now.addingTimeInterval(TimeInterval(-daysAgo) * 86_400), visibility: visibility,
                    notes: friendNotes.randomElement(using: &rng) ?? "", dishes: [], rng: &rng))
            }
        }

        // Your own history.
        if let general = versions[StarterSystems.general],
           let fine = versions[StarterSystems.fineDining],
           let fast = versions[StarterSystems.fastCasual] {
            func mine(_ slug: String, _ version: SystemVersion, _ points: [Int], daysAgo: Int,
                      notes: String, dishes: [String], spend: Decimal?, visibility: Visibility = .followers) -> Visit? {
                guard let ref = refs["demo-\(slug)"] else { return nil }
                var visit = completedVisit(
                    userID: meID, restaurantID: ref.id, version: version, scores: scoreMap(version, points),
                    visitedOn: now.addingTimeInterval(TimeInterval(-daysAgo) * 86_400), visibility: visibility,
                    notes: notes, dishes: dishes, rng: &rng)
                visit.spendPerPerson = spend
                return visit
            }

            var myVisits: [Visit] = [
                mine("bodega-sol", fast, [5, 3, 1], daysAgo: 6, notes: "Al pastor straight off the trompo. Queue out the door, worth it.",
                     dishes: ["Al pastor tacos", "Horchata"], spend: 14, visibility: .everyone),
                mine("nine-lanterns", general, [4, 2, 2, 1], daysAgo: 12, notes: "Tonkotsu was deep without being heavy. Counter seats are the move.",
                     dishes: ["Tonkotsu ramen", "Gyoza"], spend: 24, visibility: .everyone),
                mine("saltmarsh", general, [4, 2, 1, 1], daysAgo: 20, notes: "Much better than last time. The rye sourdough course alone is worth it.",
                     dishes: ["Rye sourdough", "Halibut", "Burnt honey tart"], spend: 78),
                mine("saltmarsh", general, [3, 1, 1, 1], daysAgo: 160, notes: "Opening month. Kitchen still finding its feet.",
                     dishes: ["Beet salad", "Pork chop"], spend: 70),
                mine("ostra-azul", general, [4, 1, 2, 1], daysAgo: 33, notes: "Ceviche was electric. Service a little scattered on a busy night.",
                     dishes: ["Ceviche clásico", "Lomo saltado"], spend: 52, visibility: .everyone),
                mine("copper-kettle", general, [2, 1, 1, 0], daysAgo: 48, notes: "Fine for a late breakfast, nothing more. Booths have seen better days.",
                     dishes: ["Two-egg plate"], spend: 18, visibility: .onlyMe),
            ].compactMap { $0 }

            // A visit first scored with General, then deliberately re-rated with Fine Dining.
            if var radish = mine("gilded-radish", general, [4, 2, 1, 1], daysAgo: 70,
                                 notes: "Twelve courses, not one filler. Re-rated with the Fine Dining rubric, which fits it better.",
                                 dishes: ["Tasting menu", "Wine pairing"], spend: 265, visibility: .everyone) {
                radish.revisions[0].state = .superseded
                radish.revisions.append(RatingRevision(
                    id: UUID(), visitID: radish.id, systemID: fine.systemID, versionID: fine.id,
                    scores: scoreMap(fine, [3, 3, 2, 1]), state: .active,
                    createdAt: radish.createdAt.addingTimeInterval(3 * 86_400),
                    completedAt: radish.createdAt.addingTimeInterval(3 * 86_400), total: 9))
                myVisits.append(radish)
            }

            // An unfinished rating: only Food has been scored, so it stays out of rankings.
            if let ref = refs["demo-kiln-bakery"] {
                let id = UUID()
                let created = now.addingTimeInterval(-86_400)
                myVisits.append(Visit(
                    id: id, userID: meID, restaurantID: ref.id, visitedOn: created,
                    notes: "Morning bun was unreal. Finish scoring later.", dishes: ["Morning bun"],
                    visibility: .followers,
                    revisions: [RatingRevision(id: UUID(), visitID: id, systemID: fast.systemID, versionID: fast.id,
                                               scores: [fast.criteria[0].id: 5], state: .draft, createdAt: created)],
                    createdAt: created, updatedAt: created))
            }
            state.visits.append(contentsOf: myVisits)
        }

        state.saved[meID] = ["harbor-light", "paper-crane", "little-furnace", "tandoor-lane"].enumerated().compactMap { index, slug in
            refs["demo-\(slug)"].map { SavedPlace(restaurantID: $0.id, savedAt: now.addingTimeInterval(TimeInterval(-index - 1) * 86_400)) }
        }
        return state
    }

    // MARK: Helpers

    private static let friendNotes = [
        "Would go back for the same order.",
        "Solid. Nothing I'd change, nothing I'd rave about.",
        "Go early, it fills up fast.",
        "The kitchen clearly cares.",
        "Good, but I've had better versions nearby.",
        "Great for a group, order widely.",
        "",
    ]

    private static func criterion(_ name: String, _ guidance: String, _ levels: [String]) -> Criterion {
        Criterion(id: UUID(), name: name, guidance: guidance, maxPoints: levels.count - 1,
                  levels: levels.enumerated().map { ScoreLevel(points: $0, label: $1, detail: $1 + ".") })
    }

    static func scoreMap(_ version: SystemVersion, _ points: [Int]) -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: zip(version.criteria.map(\.id), points))
    }

    private static func seededScores(version: SystemVersion, quality: Double, rng: inout SplitMix64) -> [UUID: Int] {
        var scores: [UUID: Int] = [:]
        for criterion in version.criteria {
            let noise = Double.random(in: -0.75...0.75, using: &rng)
            let raw = (quality * Double(criterion.maxPoints) + noise).rounded()
            scores[criterion.id] = min(max(Int(raw), 0), criterion.maxPoints)
        }
        return scores
    }

    private static func completedVisit(userID: UUID, restaurantID: UUID, version: SystemVersion, scores: [UUID: Int],
                                       visitedOn: Date, visibility: Visibility, notes: String, dishes: [String],
                                       rng: inout SplitMix64) -> Visit {
        let id = UUID()
        let created = visitedOn.addingTimeInterval(Double.random(in: 3_600...40_000, using: &rng))
        return Visit(
            id: id, userID: userID, restaurantID: restaurantID, visitedOn: visitedOn, notes: notes, dishes: dishes,
            visibility: visibility,
            revisions: [RatingRevision(id: UUID(), visitID: id, systemID: version.systemID, versionID: version.id,
                                       scores: scores, state: .active, createdAt: created, completedAt: created,
                                       total: RatingEngine.completedTotal(scores: scores, version: version))],
            createdAt: created, updatedAt: created)
    }
}

/// Small deterministic generator so the seeded demo looks the same on every install.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
