import Foundation

enum RatingIssue: Hashable {
    case unknownCriterion(UUID)
    case outOfRange(criterionID: UUID, name: String, score: Int, max: Int)
    case unanswered(criterionID: UUID, name: String)

    var message: String {
        switch self {
        case .unknownCriterion:
            "A score was given for a criterion that is not part of this system."
        case .outOfRange(_, let name, let score, let max):
            "\(score) is not a valid score for “\(name)” (0–\(max))."
        case .unanswered(_, let name):
            "Choose a score for “\(name)”."
        }
    }
}

/// The one place totals come from. A total is always the sum of criterion scores.
enum RatingEngine {
    static func issues(scores: [UUID: Int], version: SystemVersion, requireComplete: Bool) -> [RatingIssue] {
        var issues: [RatingIssue] = []
        let known = Set(version.criteria.map(\.id))
        for id in scores.keys.sorted(by: { $0.uuidString < $1.uuidString }) where !known.contains(id) {
            issues.append(.unknownCriterion(id))
        }
        for criterion in version.criteria {
            if let score = scores[criterion.id] {
                if score < 0 || score > criterion.maxPoints {
                    issues.append(.outOfRange(criterionID: criterion.id, name: criterion.name,
                                              score: score, max: criterion.maxPoints))
                }
            } else if requireComplete {
                issues.append(.unanswered(criterionID: criterion.id, name: criterion.name))
            }
        }
        return issues
    }

    static func isComplete(scores: [UUID: Int], version: SystemVersion) -> Bool {
        issues(scores: scores, version: version, requireComplete: true).isEmpty
    }

    /// Sum of the answered criteria. Use `completedTotal` when the rating must be whole.
    static func runningTotal(scores: [UUID: Int], version: SystemVersion) -> Int {
        version.criteria.reduce(0) { $0 + (scores[$1.id] ?? 0) }
    }

    static func completedTotal(scores: [UUID: Int], version: SystemVersion) -> Int? {
        isComplete(scores: scores, version: version) ? runningTotal(scores: scores, version: version) : nil
    }

    static func answeredCount(scores: [UUID: Int], version: SystemVersion) -> Int {
        version.criteria.filter { scores[$0.id] != nil }.count
    }
}

// MARK: - Personal rankings

enum SystemScope: Hashable {
    /// Every rubric side by side. Scores are labelled because they are not directly comparable.
    case allSystems
    case version(systemID: UUID, versionID: UUID)
}

struct RankedRestaurant: Identifiable, Hashable {
    var restaurantID: UUID
    var visit: Visit
    var revision: RatingRevision
    var total: Int
    /// Competition rank: equal totals share a rank and the next rank skips (1, 2, 2, 4).
    var rank: Int
    var isTied: Bool
    var completedVisitCount: Int

    var id: UUID { restaurantID }
}

enum RankingEngine {
    /// The rating that represents each restaurant: the latest completed visit within the scope.
    /// Drafts and superseded revisions never count.
    static func latestRatings(visits: [Visit], scope: SystemScope) -> [UUID: (visit: Visit, revision: RatingRevision)] {
        var latest: [UUID: (visit: Visit, revision: RatingRevision)] = [:]
        for visit in visits {
            guard let revision = visit.activeRevision, revision.total != nil else { continue }
            if case .version(_, let versionID) = scope, revision.versionID != versionID { continue }
            if let current = latest[visit.restaurantID], !isLater(visit, than: current.visit) { continue }
            latest[visit.restaurantID] = (visit, revision)
        }
        return latest
    }

    /// Ranks by total, highest first. Equal totals stay tied; `nameFor` only fixes the order
    /// rows are listed in within a tie and never affects rank.
    static func rank(visits: [Visit], scope: SystemScope, nameFor: (UUID) -> String = { _ in "" }) -> [RankedRestaurant] {
        let latest = latestRatings(visits: visits, scope: scope)
        let completedCounts = Dictionary(grouping: visits.filter(\.isCompleted), by: \.restaurantID).mapValues(\.count)
        let ordered = latest.values.sorted { lhs, rhs in
            let (l, r) = (lhs.revision.total ?? 0, rhs.revision.total ?? 0)
            if l != r { return l > r }
            let (ln, rn) = (nameFor(lhs.visit.restaurantID), nameFor(rhs.visit.restaurantID))
            if ln != rn { return ln.localizedCaseInsensitiveCompare(rn) == .orderedAscending }
            return lhs.visit.restaurantID.uuidString < rhs.visit.restaurantID.uuidString
        }
        let totalCounts = Dictionary(grouping: ordered, by: { $0.revision.total ?? 0 }).mapValues(\.count)

        var result: [RankedRestaurant] = []
        for (index, entry) in ordered.enumerated() {
            let total = entry.revision.total ?? 0
            let rank = result.last.map { $0.total == total ? $0.rank : index + 1 } ?? 1
            result.append(RankedRestaurant(
                restaurantID: entry.visit.restaurantID, visit: entry.visit, revision: entry.revision,
                total: total, rank: rank, isTied: (totalCounts[total] ?? 0) > 1,
                completedVisitCount: completedCounts[entry.visit.restaurantID] ?? 0))
        }
        return result
    }

    static func isLater(_ lhs: Visit, than rhs: Visit) -> Bool {
        let (l, r) = (Calendar.current.startOfDay(for: lhs.visitedOn), Calendar.current.startOfDay(for: rhs.visitedOn))
        return l != r ? l > r : lhs.createdAt > rhs.createdAt
    }

    /// How many restaurants sit at each total, for the profile's score distribution.
    static func distribution(of ranked: [RankedRestaurant]) -> [Int] {
        var buckets = Array(repeating: 0, count: RankingRules.totalPoints + 1)
        for entry in ranked where buckets.indices.contains(entry.total) { buckets[entry.total] += 1 }
        return buckets
    }
}

// MARK: - Community scores

struct CriterionAverage: Hashable, Identifiable {
    var criterion: Criterion
    var average: Double

    var id: UUID { criterion.id }
}

struct CommunityScore: Identifiable, Hashable {
    var systemID: UUID
    var versionID: UUID
    var systemName: String
    var versionNumber: Int
    var userCount: Int
    var average: Double
    var criterionAverages: [CriterionAverage]

    var id: UUID { versionID }
    var isLimited: Bool { userCount < RankingRules.limitedRatingsThreshold }
    var formattedAverage: String { average.formatted(.number.precision(.fractionLength(1))) }
}

enum CommunityAggregator {
    /// Averages public ratings for one restaurant, one bucket per standard system version.
    ///
    /// - Each person counts once per bucket, through their latest completed visit rated with it.
    /// - Only standard systems are aggregated. Personal copies and custom systems are left out
    ///   because nobody else is scoring against the same rubric.
    /// - Different versions are never averaged together.
    static func scores(
        restaurantID: UUID,
        visits: [Visit],
        systems: [UUID: RankingSystem],
        versions: [UUID: SystemVersion]
    ) -> [CommunityScore] {
        struct Key: Hashable { var userID: UUID; var versionID: UUID }
        var latest: [Key: (visit: Visit, revision: RatingRevision)] = [:]

        for visit in visits where visit.restaurantID == restaurantID && VisibilityRules.countsTowardCommunity(visit) {
            guard let revision = visit.activeRevision, revision.total != nil,
                  let system = systems[revision.systemID], system.isStandard,
                  versions[revision.versionID] != nil else { continue }
            let key = Key(userID: visit.userID, versionID: revision.versionID)
            if let current = latest[key], !RankingEngine.isLater(visit, than: current.visit) { continue }
            latest[key] = (visit, revision)
        }

        let byVersion = Dictionary(grouping: latest.values, by: { $0.revision.versionID })
        return byVersion.compactMap { versionID, entries -> CommunityScore? in
            guard let version = versions[versionID], let system = systems[version.systemID] else { return nil }
            let count = Double(entries.count)
            let average = Double(entries.reduce(0) { $0 + ($1.revision.total ?? 0) }) / count
            let criteria = version.criteria.map { criterion in
                CriterionAverage(criterion: criterion,
                                 average: Double(entries.reduce(0) { $0 + ($1.revision.scores[criterion.id] ?? 0) }) / count)
            }
            return CommunityScore(systemID: system.id, versionID: versionID, systemName: system.name,
                                  versionNumber: version.number, userCount: entries.count,
                                  average: average, criterionAverages: criteria)
        }
        .sorted { ($0.userCount, $1.systemName) > ($1.userCount, $0.systemName) }
    }
}
