import Foundation

/// What a report is about. The associated ID is the row being reported.
enum ReportTarget: Hashable {
    case visit(UUID)
    case photo(UUID)
    case user(UUID)

    var kind: ReportTargetKind {
        switch self {
        case .visit: .visit
        case .photo: .photo
        case .user: .user
        }
    }

    var id: UUID {
        switch self {
        case .visit(let id), .photo(let id), .user(let id): id
        }
    }
}

enum ReportTargetKind: String, Codable {
    case visit, photo, user

    var title: String {
        switch self {
        case .visit: "Review"
        case .photo: "Photo"
        case .user: "Person"
        }
    }

    /// The moderator's "remove" button. For a person, the content is their names.
    var removeTitle: String {
        switch self {
        case .visit: "Remove review"
        case .photo: "Remove photo"
        case .user: "Reset names"
        }
    }
}

enum ReportReason: String, Codable, CaseIterable, Identifiable {
    case spam, harassment, hate, sexual, violence, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spam: "Spam or fake"
        case .harassment: "Harassment or bullying"
        case .hate: "Hate speech"
        case .sexual: "Sexual content"
        case .violence: "Violence or threats"
        case .other: "Something else"
        }
    }
}

enum ReportStatus: String, Codable {
    case open, actioned, dismissed
}

/// The reported content as it was when the report was filed, so deleting it hides nothing.
struct ReportSnapshot: Codable, Hashable {
    var username = ""
    var displayName = ""
    var notes = ""
    var dishes: [String] = []
    var systemName: String?
    var photoPaths: [String] = []
}

struct ContentReport: Identifiable, Codable, Hashable {
    var id: UUID
    var targetKind: ReportTargetKind
    var targetID: UUID
    var reportedUserID: UUID
    var reason: ReportReason
    var details: String
    var snapshot: ReportSnapshot
    var status: ReportStatus = .open
    var createdAt: Date
    /// Kept only in the demo, which has no database constraint to stop repeat reports.
    var reporterID: UUID?
}

enum ModerationAction: String, CaseIterable {
    case dismiss
    case removeContent = "remove_content"
    case ban
    case deleteAccount = "delete_account"
}

/// Wording shared by the screens that explain how moderation works.
enum CommunityRules {
    static let summary = "There is no tolerance for objectionable content or abusive people. Keep reviews about the food and the place. No hate speech, harassment, threats, sexual content or spam, in words or photos."
    static let enforcement = "Anyone can report a review, a photo or a person. Reports are reviewed within 24 hours, and content that breaks these rules is removed. Accounts that break them are banned."
}

/// The demo's copy of the server's text filter. The list that matters in live use is
/// `app_private.blocked_terms` in the database. This is only enough to show the behaviour.
enum ContentFilter {
    static let refusal = "That wording isn't allowed under the community rules. Please change it."

    private static let terms = ["kill yourself", "kys", "hang yourself", "heil hitler"]

    static func allows(_ text: String) -> Bool {
        let normalized = normalize(text)
        return !terms.contains { normalized.range(of: pattern(for: $0), options: .regularExpression) != nil }
    }

    /// Mirrors `app_private.normalize_text`.
    static func normalize(_ text: String) -> String {
        let swaps: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "@": "a", "$": "s"]
        return String(text.lowercased().map { swaps[$0] ?? $0 })
            .replacingOccurrences(of: "[^a-z]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Mirrors `app_private.term_pattern`: "kill" becomes k+i+l{2,}.
    private static func pattern(for term: String) -> String {
        let stretched = term
            .replacingOccurrences(of: "([a-z])", with: "$1+", options: .regularExpression)
            .replacingOccurrences(of: "([a-z])\\+\\1\\+", with: "$1{2,}", options: .regularExpression)
        return "\\b\(stretched)\\b"
    }
}
