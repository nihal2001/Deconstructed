import Foundation

/// What one selectable score means for a criterion.
struct ScoreLevel: Codable, Hashable, Identifiable {
    var points: Int
    var label: String
    var detail: String

    var id: Int { points }

    var displayLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (points == 1 ? "1 point" : "\(points) points") : trimmed
    }
}

struct Criterion: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var guidance: String
    var maxPoints: Int
    /// One entry per selectable score, 0...maxPoints, in ascending order.
    var levels: [ScoreLevel]
    /// Set while editing when the maximum changed and the descriptions have not been re-read.
    var needsLevelReview = false

    static func blank(maxPoints: Int = 1) -> Criterion {
        Criterion(id: UUID(), name: "", guidance: "", maxPoints: maxPoints,
                  levels: (0...maxPoints).map { ScoreLevel(points: $0, label: "", detail: "") })
    }

    func level(for points: Int) -> ScoreLevel? {
        levels.first { $0.points == points }
    }

    /// Changes the maximum, keeping descriptions for scores that still exist and flagging the
    /// criterion for review, because the same number now means something different.
    mutating func setMaxPoints(_ newMax: Int) {
        let clamped = min(max(newMax, 1), RankingRules.totalPoints)
        guard clamped != maxPoints else { return }
        maxPoints = clamped
        levels = (0...clamped).map { points in
            level(for: points) ?? ScoreLevel(points: points, label: "", detail: "")
        }
        needsLevelReview = true
    }
}

/// An immutable, published definition. Ratings point at one of these forever.
struct SystemVersion: Identifiable, Codable, Hashable {
    var id: UUID
    var systemID: UUID
    var number: Int
    var criteria: [Criterion]
    var publishedAt: Date

    func criterion(_ id: UUID) -> Criterion? { criteria.first { $0.id == id } }

    var allocationSummary: String {
        criteria.map { "\($0.name) \($0.maxPoints)" }.joined(separator: " · ")
    }
}

/// The editable working copy of a system. Becomes a `SystemVersion` when published.
struct SystemDraft: Codable, Hashable {
    var name: String
    var summary: String
    var criteria: [Criterion]

    var allocatedPoints: Int { criteria.reduce(0) { $0 + $1.maxPoints } }

    static var blank: SystemDraft {
        SystemDraft(name: "", summary: "", criteria: [])
    }
}

struct RankingSystem: Identifiable, Codable, Hashable {
    var id: UUID
    /// `nil` for the shared standard systems everyone starts with.
    var ownerID: UUID?
    /// Which starter this is, or was copied from.
    var templateKey: String?
    /// Set on a personal copy made by editing or duplicating another system.
    var forkedFromSystemID: UUID?
    var name: String
    var summary: String
    var isArchived = false
    var currentVersionID: UUID?
    /// Unpublished edits, visible only to the owner.
    var draft: SystemDraft?
    var createdAt: Date
    var updatedAt: Date

    var isStandard: Bool { ownerID == nil }
    var isDraftOnly: Bool { currentVersionID == nil }
    var isSelectableForNewRatings: Bool { !isArchived && currentVersionID != nil }
}

struct SystemCatalog: Codable, Hashable {
    var systems: [RankingSystem] = []
    var versions: [SystemVersion] = []
}

// MARK: - Validation

enum RankingRules {
    static let totalPoints = 10
    static let limitedRatingsThreshold = 5
}

enum SystemIssue: Hashable, Identifiable {
    case missingName
    case noCriteria
    case allocation(allocated: Int)
    case criterionMissingName(criterionID: UUID, position: Int)
    case duplicateCriterionName(name: String)
    case invalidMaximum(criterionID: UUID, name: String)
    case missingDescriptions(criterionID: UUID, name: String, points: [Int])
    case needsReview(criterionID: UUID, name: String)

    var id: String { message }

    var criterionID: UUID? {
        switch self {
        case .criterionMissingName(let id, _), .invalidMaximum(let id, _),
             .missingDescriptions(let id, _, _), .needsReview(let id, _): id
        default: nil
        }
    }

    var message: String {
        switch self {
        case .missingName:
            "Give the system a name."
        case .noCriteria:
            "Add at least one criterion."
        case .allocation(let allocated):
            allocated < RankingRules.totalPoints
                ? "Allocate \(RankingRules.totalPoints - allocated) more point\(RankingRules.totalPoints - allocated == 1 ? "" : "s") so the criteria total 10."
                : "Remove \(allocated - RankingRules.totalPoints) point\(allocated - RankingRules.totalPoints == 1 ? "" : "s") so the criteria total 10."
        case .criterionMissingName(_, let position):
            "Name criterion \(position)."
        case .duplicateCriterionName(let name):
            "Two criteria are called “\(name)”. Give each a distinct name."
        case .invalidMaximum(_, let name):
            "“\(name)” needs a maximum of at least 1 point."
        case .missingDescriptions(_, let name, let points):
            "Describe what \(points.map(String.init).joined(separator: ", ")) means for “\(name)”."
        case .needsReview(_, let name):
            "The maximum for “\(name)” changed. Review its score descriptions."
        }
    }
}

enum SystemValidator {
    /// Everything that stops a draft from being activated. Empty means it can be published.
    static func issues(for draft: SystemDraft) -> [SystemIssue] {
        var issues: [SystemIssue] = []
        if draft.name.isBlank { issues.append(.missingName) }
        if draft.criteria.isEmpty { issues.append(.noCriteria) }

        var seen = Set<String>()
        for (index, criterion) in draft.criteria.enumerated() {
            let name = criterion.name.trimmed
            let label = name.isEmpty ? "Criterion \(index + 1)" : name
            if name.isEmpty {
                issues.append(.criterionMissingName(criterionID: criterion.id, position: index + 1))
            } else if !seen.insert(name.lowercased()).inserted {
                issues.append(.duplicateCriterionName(name: name))
            }
            if criterion.maxPoints < 1 {
                issues.append(.invalidMaximum(criterionID: criterion.id, name: label))
                continue
            }
            let missing = (0...criterion.maxPoints).filter { points in
                criterion.level(for: points)?.detail.isBlank ?? true
            }
            if !missing.isEmpty || criterion.levels.count != criterion.maxPoints + 1 {
                issues.append(.missingDescriptions(criterionID: criterion.id, name: label, points: missing))
            }
            if criterion.needsLevelReview {
                issues.append(.needsReview(criterionID: criterion.id, name: label))
            }
        }

        if !draft.criteria.isEmpty, draft.allocatedPoints != RankingRules.totalPoints {
            issues.append(.allocation(allocated: draft.allocatedPoints))
        }
        return issues
    }

    static func canActivate(_ draft: SystemDraft) -> Bool { issues(for: draft).isEmpty }

    /// Normalises a valid draft into the criteria stored on a published version.
    static func publishableCriteria(from draft: SystemDraft) -> [Criterion] {
        draft.criteria.map { criterion in
            var copy = criterion
            copy.name = criterion.name.trimmed
            copy.guidance = criterion.guidance.trimmed
            copy.needsLevelReview = false
            copy.levels = criterion.levels.sorted { $0.points < $1.points }.map {
                ScoreLevel(points: $0.points, label: $0.label.trimmed, detail: $0.detail.trimmed)
            }
            return copy
        }
    }

    /// Only a change to the criteria needs a new version; renaming a system does not.
    /// Criterion IDs are ignored: each version gets its own, so only the content is compared.
    static func requiresNewVersion(_ draft: SystemDraft, comparedTo version: SystemVersion?) -> Bool {
        guard let version else { return true }
        func content(_ criteria: [Criterion]) -> [Criterion] {
            criteria.map { var copy = $0; copy.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!; return copy }
        }
        return content(publishableCriteria(from: draft)) != content(version.criteria)
    }

    /// The criteria for a brand-new version. Every version owns its criterion IDs, so a
    /// score can only ever refer to a criterion of the version it was given under.
    static func newVersionCriteria(from draft: SystemDraft) -> [Criterion] {
        publishableCriteria(from: draft).map { var copy = $0; copy.id = UUID(); return copy }
    }
}

extension RankingSystem {
    /// The starting point for editing: saved draft if there is one, else the current version.
    func editableDraft(currentVersion: SystemVersion?) -> SystemDraft {
        draft ?? SystemDraft(name: name, summary: summary, criteria: currentVersion?.criteria ?? [])
    }
}

extension SystemDraft {
    /// A copy with fresh criterion IDs, for duplicating a system or forking a standard one.
    func duplicated(named newName: String) -> SystemDraft {
        SystemDraft(name: newName, summary: summary, criteria: criteria.map {
            var copy = $0
            copy.id = UUID()
            return copy
        })
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var isBlank: Bool { trimmed.isEmpty }
}
