import CoreLocation
import Foundation

struct Coordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    var clLocation: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    func distance(to other: Coordinate) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

/// Who may read a review. Only `everyone` reviews feed community averages.
enum Visibility: String, Codable, CaseIterable, Identifiable {
    case everyone = "public"
    case followers
    case onlyMe = "private"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyone: "Public"
        case .followers: "Followers"
        case .onlyMe: "Private"
        }
    }

    var detail: String {
        switch self {
        case .everyone: "Anyone can read it, and it counts toward community scores."
        case .followers: "Only people who follow you can read it. Not counted in community scores."
        case .onlyMe: "Only you can read it. Not counted in community scores."
        }
    }

    var symbol: String {
        switch self {
        case .everyone: "globe"
        case .followers: "person.2"
        case .onlyMe: "lock"
        }
    }
}

struct UserProfile: Identifiable, Codable, Hashable {
    var id: UUID
    var username: String
    var displayName: String
    var defaultVisibility: Visibility = .followers
    var defaultSystemID: UUID?
    /// Standard systems this person has put away. They stay readable on old ratings.
    var archivedStandardSystemIDs: [UUID] = []

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2).compactMap(\.first)
        return parts.isEmpty ? "?" : String(parts).uppercased()
    }
}

/// The app's own record of a restaurant. It holds a provider place ID and nothing else that
/// belongs to the provider, apart from a coordinate that is only kept for a limited time.
struct RestaurantRef: Identifiable, Codable, Hashable {
    /// Google allows latitude/longitude to be cached for at most 30 consecutive days.
    static let coordinateLifetime: TimeInterval = 30 * 24 * 60 * 60

    var id: UUID
    var provider: String
    var providerPlaceID: String
    var cachedCoordinate: Coordinate?
    var coordinateCachedAt: Date?

    func freshCoordinate(now: Date = .now) -> Coordinate? {
        guard let cachedCoordinate, let coordinateCachedAt,
              now.timeIntervalSince(coordinateCachedAt) < Self.coordinateLifetime else { return nil }
        return cachedCoordinate
    }
}

struct SavedPlace: Codable, Hashable {
    var restaurantID: UUID
    var savedAt: Date
}

// MARK: - Provider content (held in memory only, never written to the backend)

enum PlaceDetailLevel: Int, Comparable, Codable {
    /// Coordinate only. Cheapest request; enough to draw a pin.
    case location = 0
    /// Name, address, cuisine and area. What lists and the profile header need.
    case core = 1
    /// Price level, website, phone and hours. Loaded only when the user asks.
    case extended = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct Place: Identifiable, Hashable {
    var placeID: String
    var level: PlaceDetailLevel
    var name: String?
    var address: String?
    var coordinate: Coordinate?
    var cuisine: String?
    var area: String?
    var priceLevel: Int?
    var website: URL?
    var phone: String?
    var openingHours: [String] = []
    /// Third-party attribution text the provider requires next to the details.
    var thirdPartyAttribution: String?
    var isDemo = false

    var id: String { placeID }

    var subtitle: String {
        [cuisine, area].compactMap { $0 }.joined(separator: " · ")
    }

    /// Keeps the richer of two copies so a cheap refresh never throws away loaded fields.
    func merged(with newer: Place) -> Place {
        var result = newer.level >= level ? newer : self
        let other = newer.level >= level ? self : newer
        result.name = result.name ?? other.name
        result.address = result.address ?? other.address
        result.coordinate = result.coordinate ?? other.coordinate
        result.cuisine = result.cuisine ?? other.cuisine
        result.area = result.area ?? other.area
        result.priceLevel = result.priceLevel ?? other.priceLevel
        result.website = result.website ?? other.website
        result.phone = result.phone ?? other.phone
        if result.openingHours.isEmpty { result.openingHours = other.openingHours }
        result.thirdPartyAttribution = result.thirdPartyAttribution ?? other.thirdPartyAttribution
        return result
    }
}

struct PlaceSuggestion: Identifiable, Hashable {
    var placeID: String
    var title: String
    var subtitle: String?
    var isDemo = false

    var id: String { placeID }
}

// MARK: - Visits and ratings

enum RevisionState: String, Codable {
    case draft
    case active
    case superseded
}

/// One scoring of a visit against one exact system version. Completed revisions never change;
/// re-rating adds a new revision and supersedes the old one.
struct RatingRevision: Identifiable, Codable, Hashable {
    var id: UUID
    var visitID: UUID
    var systemID: UUID
    var versionID: UUID
    /// Criterion ID → chosen points. Missing key means "not answered yet".
    var scores: [UUID: Int]
    var state: RevisionState
    var createdAt: Date
    var completedAt: Date?
    /// Derived from `scores` when the revision is completed. Never entered directly.
    var total: Int?
}

struct VisitPhoto: Identifiable, Codable, Hashable {
    var id: UUID
    var storagePath: String
}

struct Visit: Identifiable, Codable, Hashable {
    var id: UUID
    var userID: UUID
    var restaurantID: UUID
    var visitedOn: Date
    var notes: String = ""
    var dishes: [String] = []
    var spendPerPerson: Decimal?
    var currencyCode: String = Locale.current.currency?.identifier ?? "USD"
    var visibility: Visibility
    var photos: [VisitPhoto] = []
    var revisions: [RatingRevision] = []
    var createdAt: Date
    var updatedAt: Date

    var activeRevision: RatingRevision? { revisions.first { $0.state == .active } }
    var draftRevision: RatingRevision? { revisions.first { $0.state == .draft } }
    var isCompleted: Bool { activeRevision != nil }

    /// Earlier ratings of this visit, newest first.
    var supersededRevisions: [RatingRevision] {
        revisions.filter { $0.state == .superseded }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }
}

/// Editable, non-score fields of a visit.
struct VisitDetails: Hashable {
    var visitedOn: Date = .now
    var notes: String = ""
    var dishes: [String] = []
    var spendPerPerson: Decimal?
    var currencyCode: String = Locale.current.currency?.identifier ?? "USD"
    var visibility: Visibility = .followers

    init() {}

    init(_ visit: Visit) {
        visitedOn = visit.visitedOn
        notes = visit.notes
        dishes = visit.dishes
        spendPerPerson = visit.spendPerPerson
        currencyCode = visit.currencyCode
        visibility = visit.visibility
    }
}

struct FeedItem: Identifiable, Hashable {
    var visit: Visit
    var author: UserProfile

    var id: UUID { visit.id }
}

enum VisibilityRules {
    /// The single rule for who may read a visit. The backend's row-level security mirrors it.
    static func canView(_ visit: Visit, viewerID: UUID?, viewerFollowsAuthor: Bool) -> Bool {
        if visit.userID == viewerID { return true }
        guard visit.isCompleted else { return false }
        switch visit.visibility {
        case .everyone: return true
        case .followers: return viewerFollowsAuthor
        case .onlyMe: return false
        }
    }

    static func countsTowardCommunity(_ visit: Visit) -> Bool {
        visit.isCompleted && visit.visibility == .everyone
    }
}
