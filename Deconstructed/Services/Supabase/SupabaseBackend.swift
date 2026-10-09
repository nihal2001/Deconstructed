import Foundation
import Supabase

/// The live backend. It is a thin client: ownership, visibility, score ranges and totals are
/// all enforced by the database (see supabase/migrations), not by this file.
@MainActor
final class SupabaseBackend: BackendService {
    let isDemo = false

    private let client: SupabaseClient
    private static let photoBucket = "visit-photos"

    init(url: URL, anonKey: String) {
        client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }

    // MARK: Session

    func restoreSession() async throws -> UserProfile? {
        guard let session = try? await client.auth.session else { return nil }
        return try await loadProfile(id: session.user.id)
    }

    func signInWithApple(idToken: String, nonce: String, displayName: String?) async throws -> UserProfile {
        let session = try await wrap {
            try await self.client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce))
        }
        var profile = try await loadProfile(id: session.user.id)
        // Apple only shares the name on the very first sign-in, so keep it if we get it.
        if let displayName = displayName?.trimmed, !displayName.isEmpty, profile.displayName == "New member" {
            profile.displayName = displayName
            profile = try await updateProfile(profile)
        }
        return profile
    }

    func signInDemo() async throws -> UserProfile {
        throw BackendError.notAllowed("The demo account is only available when no backend is configured.")
    }

    func signOut() async throws {
        try await wrap { try await self.client.auth.signOut() }
    }

    func deleteAccount() async throws {
        // An Edge Function does this because it needs the service role: it removes the
        // user's photos from Storage, then the auth user, which cascades to every table.
        try await wrap { try await self.client.functions.invoke("delete-account") }
        try? await client.auth.signOut(scope: .local)
    }

    func updateProfile(_ profile: UserProfile) async throws -> UserProfile {
        let row: ProfileRow = try await wrap {
            try await self.client.from("profiles")
                .update(ProfileUpdate(profile))
                .eq("id", value: profile.id)
                .select(ProfileRow.columns)
                .single()
                .execute().value
        }
        return row.model
    }

    private func loadProfile(id: UUID) async throws -> UserProfile {
        let row: ProfileRow = try await wrap {
            try await self.client.from("profiles").select(ProfileRow.columns).eq("id", value: id).single().execute().value
        }
        return row.model
    }

    private func userID() async throws -> UUID {
        guard let session = try? await client.auth.session else { throw BackendError.notSignedIn }
        return session.user.id
    }

    // MARK: Ranking systems

    func loadCatalog() async throws -> SystemCatalog {
        let uid = try await userID()
        let rows: [SystemRow] = try await wrap {
            try await self.client.from("ranking_systems")
                .select(SystemRow.columnsWithDefinitions)
                .or("owner_id.is.null,owner_id.eq.\(uid.uuidString)")
                .execute().value
        }
        return catalog(from: rows)
    }

    func loadDefinitions(versionIDs: [UUID]) async throws -> SystemCatalog {
        guard !versionIDs.isEmpty else { return SystemCatalog() }
        // Row-level security decides which of these the caller may actually read.
        let versions: [VersionRow] = try await wrap {
            try await self.client.from("ranking_system_versions")
                .select(VersionRow.columns)
                .in("id", values: versionIDs)
                .execute().value
        }
        let systemIDs = Array(Set(versions.map(\.system_id)))
        guard !systemIDs.isEmpty else { return SystemCatalog() }
        let systems: [SystemRow] = try await wrap {
            try await self.client.from("ranking_systems").select(SystemRow.columns).in("id", values: systemIDs).execute().value
        }
        return SystemCatalog(systems: systems.map(\.model), versions: versions.map(\.model))
    }

    func saveDraft(systemID: UUID?, draft: SystemDraft, forkedFrom: UUID?) async throws -> RankingSystem {
        let uid = try await userID()
        let name = draft.name.trimmed.isEmpty ? "Untitled system" : draft.name.trimmed
        let id: UUID
        if let systemID {
            id = systemID
            // While a system has never been published, its list name follows the draft.
            _ = try await wrap {
                try await self.client.from("ranking_systems")
                    .update(SystemNameUpdate(name: name, description: draft.summary.trimmed))
                    .eq("id", value: systemID)
                    .is("current_version_id", value: nil)
                    .execute()
            }
        } else {
            id = UUID()
            var templateKey: String?
            if let forkedFrom {
                let source: [SystemRow] = try await wrap {
                    try await self.client.from("ranking_systems").select(SystemRow.columns).eq("id", value: forkedFrom).execute().value
                }
                templateKey = source.first?.template_key
            }
            _ = try await wrap {
                try await self.client.from("ranking_systems")
                    .insert(SystemInsert(id: id, owner_id: uid, template_key: templateKey, forked_from_system_id: forkedFrom,
                                         name: name, description: draft.summary.trimmed))
                    .execute()
            }
        }
        _ = try await wrap {
            try await self.client.from("ranking_system_drafts")
                .upsert(DraftUpsert(system_id: id, definition: draft, updated_at: Date()), onConflict: "system_id")
                .execute()
        }
        guard let system = try await loadSystems(ids: [id]).systems.first else { throw BackendError.notFound }
        return system
    }

    func publish(systemID: UUID, draft: SystemDraft) async throws -> SystemCatalog {
        let criteria = SystemValidator.publishableCriteria(from: draft).map {
            CriterionPayload(name: $0.name, guidance: $0.guidance, max_points: $0.maxPoints,
                             levels: $0.levels.map { LevelPayload(points: $0.points, label: $0.label, description: $0.detail) })
        }
        _ = try await wrap {
            try await self.client.rpc("publish_system_version", params: PublishParams(
                p_system_id: systemID, p_name: draft.name.trimmed, p_description: draft.summary.trimmed, p_criteria: criteria)
            ).execute()
        }
        return try await loadSystems(ids: [systemID])
    }

    func setArchived(systemID: UUID, archived: Bool) async throws -> RankingSystem {
        _ = try await wrap {
            try await self.client.from("ranking_systems").update(["is_archived": archived]).eq("id", value: systemID).execute()
        }
        guard let system = try await loadSystems(ids: [systemID]).systems.first else { throw BackendError.notFound }
        return system
    }

    func deleteSystem(systemID: UUID) async throws {
        do {
            _ = try await wrap {
                try await self.client.from("ranking_systems").delete().eq("id", value: systemID).execute()
            }
        } catch BackendError.notAllowed {
            // The database refuses to drop a version that a rating still points at.
            throw BackendError.notAllowed("This system has ratings, so it can't be deleted. Archive it instead to keep those ratings readable.")
        }
    }

    private func loadSystems(ids: [UUID]) async throws -> SystemCatalog {
        let rows: [SystemRow] = try await wrap {
            try await self.client.from("ranking_systems").select(SystemRow.columnsWithDefinitions).in("id", values: ids).execute().value
        }
        return catalog(from: rows)
    }

    private func catalog(from rows: [SystemRow]) -> SystemCatalog {
        SystemCatalog(systems: rows.map(\.model), versions: rows.flatMap { ($0.ranking_system_versions ?? []).map(\.model) })
    }

    // MARK: Restaurants and saved places

    func ensureRestaurant(provider: String, placeID: String, coordinate: Coordinate?) async throws -> RestaurantRef {
        let row: RestaurantRow = try await wrap {
            try await self.client.rpc("ensure_restaurant", params: EnsureRestaurantParams(
                p_provider: provider, p_place_id: placeID, p_lat: coordinate?.latitude, p_lng: coordinate?.longitude)
            ).execute().value
        }
        return row.model
    }

    func loadRestaurants(ids: [UUID]) async throws -> [RestaurantRef] {
        guard !ids.isEmpty else { return [] }
        let rows: [RestaurantRow] = try await wrap {
            try await self.client.from("restaurants").select().in("id", values: ids).execute().value
        }
        return rows.map(\.model)
    }

    func cacheCoordinate(restaurantID: UUID, coordinate: Coordinate) async throws -> RestaurantRef {
        let row: RestaurantRow = try await wrap {
            try await self.client.rpc("cache_restaurant_location", params: CacheLocationParams(
                p_restaurant_id: restaurantID, p_lat: coordinate.latitude, p_lng: coordinate.longitude)
            ).execute().value
        }
        return row.model
    }

    func loadSaved() async throws -> [SavedPlace] {
        let uid = try await userID()
        let rows: [SavedRow] = try await wrap {
            try await self.client.from("saved_places").select("restaurant_id,created_at").eq("user_id", value: uid).execute().value
        }
        return rows.map { SavedPlace(restaurantID: $0.restaurant_id, savedAt: $0.created_at) }
    }

    func setSaved(restaurantID: UUID, saved: Bool) async throws {
        let uid = try await userID()
        _ = try await wrap {
            if saved {
                try await self.client.from("saved_places")
                    .upsert(SavedInsert(user_id: uid, restaurant_id: restaurantID), onConflict: "user_id,restaurant_id")
                    .execute()
            } else {
                try await self.client.from("saved_places").delete()
                    .eq("user_id", value: uid).eq("restaurant_id", value: restaurantID).execute()
            }
        }
    }

    // MARK: Visits and ratings

    func loadMyVisits() async throws -> [Visit] {
        let uid = try await userID()
        let rows: [VisitRow] = try await wrap {
            try await self.client.from("visits").select(VisitRow.columns).eq("user_id", value: uid).execute().value
        }
        return rows.map(\.model)
    }

    func createVisit(restaurantID: UUID, details: VisitDetails) async throws -> Visit {
        let uid = try await userID()
        let row: VisitRow = try await wrap {
            try await self.client.from("visits")
                .insert(VisitWrite(user_id: uid, restaurant_id: restaurantID, details: details))
                .select(VisitRow.columns).single().execute().value
        }
        return row.model
    }

    func updateVisit(id: UUID, details: VisitDetails) async throws -> Visit {
        let row: VisitRow = try await wrap {
            try await self.client.from("visits")
                .update(VisitWrite(user_id: nil, restaurant_id: nil, details: details))
                .eq("id", value: id)
                .select(VisitRow.columns).single().execute().value
        }
        return row.model
    }

    func deleteVisit(id: UUID) async throws {
        let visit = try await loadVisit(id: id)
        _ = try await wrap { try await self.client.from("visits").delete().eq("id", value: id).execute() }
        let paths = visit.photos.map(\.storagePath)
        if !paths.isEmpty {
            _ = try? await client.storage.from(Self.photoBucket).remove(paths: paths)
        }
    }

    func saveRating(visitID: UUID, versionID: UUID, scores: [UUID: Int], complete: Bool) async throws -> Visit {
        // Only criterion scores are sent. The database sums them; there is no total to send.
        let payload = Dictionary(uniqueKeysWithValues: scores.map { ($0.key.uuidString.lowercased(), $0.value) })
        _ = try await wrap {
            try await self.client.rpc("save_rating", params: SaveRatingParams(
                p_visit_id: visitID, p_system_version_id: versionID, p_scores: payload, p_complete: complete)
            ).execute()
        }
        return try await loadVisit(id: visitID)
    }

    func discardDraftRating(visitID: UUID) async throws -> Visit {
        _ = try await wrap {
            try await self.client.rpc("discard_draft_rating", params: ["p_visit_id": visitID]).execute()
        }
        return try await loadVisit(id: visitID)
    }

    func addPhoto(visitID: UUID, jpeg: Data) async throws -> Visit {
        let uid = try await userID()
        // The storage policy only accepts paths that start with the caller's own user ID.
        let path = "\(uid.uuidString.lowercased())/\(visitID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        _ = try await wrap {
            try await self.client.storage.from(Self.photoBucket)
                .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
        }
        _ = try await wrap {
            try await self.client.from("visit_photos")
                .insert(PhotoInsert(visit_id: visitID, user_id: uid, storage_path: path)).execute()
        }
        return try await loadVisit(id: visitID)
    }

    func removePhoto(visitID: UUID, photoID: UUID) async throws -> Visit {
        let visit = try await loadVisit(id: visitID)
        _ = try await wrap { try await self.client.from("visit_photos").delete().eq("id", value: photoID).execute() }
        if let photo = visit.photos.first(where: { $0.id == photoID }) {
            _ = try? await client.storage.from(Self.photoBucket).remove(paths: [photo.storagePath])
        }
        return try await loadVisit(id: visitID)
    }

    func photoData(_ photo: VisitPhoto) async throws -> Data {
        try await wrap { try await self.client.storage.from(Self.photoBucket).download(path: photo.storagePath) }
    }

    private func loadVisit(id: UUID) async throws -> Visit {
        let row: VisitRow = try await wrap {
            try await self.client.from("visits").select(VisitRow.columns).eq("id", value: id).single().execute().value
        }
        return row.model
    }

    // MARK: Friends and community

    func searchUsers(_ query: String) async throws -> [UserProfile] {
        let uid = try await userID()
        // Strip characters that have meaning in a PostgREST filter or a LIKE pattern.
        let needle = query.trimmed.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == " " }
        guard needle.count >= 2 else { return [] }
        let rows: [ProfileRow] = try await wrap {
            try await self.client.from("profiles")
                .select(ProfileRow.columns)
                .or("username.ilike.*\(needle)*,display_name.ilike.*\(needle)*")
                .neq("id", value: uid)
                .limit(25)
                .execute().value
        }
        return rows.map(\.model)
    }

    func loadFollowing() async throws -> [UserProfile] {
        let uid = try await userID()
        let rows: [FollowRow] = try await wrap {
            try await self.client.from("follows")
                .select("profile:profiles!follows_followee_id_fkey(\(ProfileRow.columns))")
                .eq("follower_id", value: uid).execute().value
        }
        return rows.map(\.profile.model)
    }

    func loadFollowers() async throws -> [UserProfile] {
        let uid = try await userID()
        let rows: [FollowRow] = try await wrap {
            try await self.client.from("follows")
                .select("profile:profiles!follows_follower_id_fkey(\(ProfileRow.columns))")
                .eq("followee_id", value: uid).execute().value
        }
        return rows.map(\.profile.model)
    }

    func setFollowing(userID target: UUID, following: Bool) async throws {
        let uid = try await userID()
        _ = try await wrap {
            if following {
                try await self.client.from("follows")
                    .upsert(FollowInsert(follower_id: uid, followee_id: target), onConflict: "follower_id,followee_id")
                    .execute()
            } else {
                try await self.client.from("follows").delete()
                    .eq("follower_id", value: uid).eq("followee_id", value: target).execute()
            }
        }
    }

    func removeFollower(userID target: UUID) async throws {
        let uid = try await userID()
        _ = try await wrap {
            try await self.client.from("follows").delete()
                .eq("follower_id", value: target).eq("followee_id", value: uid).execute()
        }
    }

    func loadFeed() async throws -> [FeedItem] {
        let following = try await loadFollowing()
        guard !following.isEmpty else { return [] }
        let authors = Dictionary(uniqueKeysWithValues: following.map { ($0.id, $0) })
        // Row-level security drops anything private or without a completed rating.
        let rows: [VisitRow] = try await wrap {
            try await self.client.from("visits")
                .select(VisitRow.columns)
                .in("user_id", values: following.map(\.id))
                .order("visited_on", ascending: false)
                .order("created_at", ascending: false)
                .limit(60)
                .execute().value
        }
        return rows.map(\.model).filter(\.isCompleted).compactMap { visit in
            authors[visit.userID].map { FeedItem(visit: visit, author: $0) }
        }
    }

    func loadVisits(ofUser userID: UUID) async throws -> [Visit] {
        let rows: [VisitRow] = try await wrap {
            try await self.client.from("visits")
                .select(VisitRow.columns)
                .eq("user_id", value: userID)
                .order("visited_on", ascending: false)
                .limit(100)
                .execute().value
        }
        return rows.map(\.model).filter(\.isCompleted)
    }

    func communityScores(provider: String, placeID: String) async throws -> [CommunityScore] {
        let rows: [CommunityRow] = try await wrap {
            try await self.client.rpc("community_scores", params: ["p_provider": provider, "p_place_id": placeID]).execute().value
        }
        guard !rows.isEmpty else { return [] }
        let definitions = try await loadDefinitions(versionIDs: rows.map(\.version_id))
        let versions = Dictionary(uniqueKeysWithValues: definitions.versions.map { ($0.id, $0) })
        return rows.compactMap { row in
            guard let version = versions[row.version_id] else { return nil }
            let averages = Dictionary(uniqueKeysWithValues: row.criteria.map { ($0.criterion_id, $0.average ?? 0) })
            return CommunityScore(
                systemID: row.system_id, versionID: row.version_id, systemName: row.system_name,
                versionNumber: row.version_number, userCount: row.user_count, average: row.average,
                criterionAverages: version.criteria.map { CriterionAverage(criterion: $0, average: averages[$0.id] ?? 0) })
        }
    }

    // MARK: Error mapping

    private func wrap<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as BackendError {
            throw error
        } catch let error as PostgrestError {
            switch error.code {
            case "42501", "23503": throw BackendError.notAllowed(error.message.sentenceCased)
            case "23514", "22023", "23505", "P0001", "22P02": throw BackendError.invalid(error.message.sentenceCased)
            case "PGRST116", "P0002": throw BackendError.notFound
            case "28000": throw BackendError.notSignedIn
            default: throw BackendError.other(error.message.sentenceCased)
            }
        } catch let error as URLError {
            _ = error
            throw BackendError.network
        } catch {
            throw BackendError.other(error.localizedDescription)
        }
    }
}

private extension String {
    var sentenceCased: String {
        guard let first else { return self }
        let text = first.uppercased() + dropFirst()
        return text.hasSuffix(".") ? text : text + "."
    }
}

// MARK: - Rows
// Property names mirror database columns so no key mapping is needed.

private struct ProfileRow: Decodable {
    static let columns = "id,username,display_name,default_visibility,default_system_id,archived_standard_system_ids"

    var id: UUID
    var username: String
    var display_name: String
    var default_visibility: Visibility
    var default_system_id: UUID?
    var archived_standard_system_ids: [UUID]?

    var model: UserProfile {
        UserProfile(id: id, username: username, displayName: display_name, defaultVisibility: default_visibility,
                    defaultSystemID: default_system_id, archivedStandardSystemIDs: archived_standard_system_ids ?? [])
    }
}

private struct ProfileUpdate: Encodable {
    var username: String
    var display_name: String
    var default_visibility: Visibility
    var default_system_id: UUID?
    var archived_standard_system_ids: [UUID]

    init(_ profile: UserProfile) {
        username = profile.username.trimmed.lowercased()
        display_name = profile.displayName.trimmed
        default_visibility = profile.defaultVisibility
        default_system_id = profile.defaultSystemID
        archived_standard_system_ids = profile.archivedStandardSystemIDs
    }

    // Encode nil as an explicit null so clearing the default system reaches the database.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(username, forKey: .username)
        try container.encode(display_name, forKey: .display_name)
        try container.encode(default_visibility, forKey: .default_visibility)
        try container.encode(default_system_id, forKey: .default_system_id)
        try container.encode(archived_standard_system_ids, forKey: .archived_standard_system_ids)
    }

    enum CodingKeys: String, CodingKey {
        case username, display_name, default_visibility, default_system_id, archived_standard_system_ids
    }
}

private struct FollowRow: Decodable {
    var profile: ProfileRow
}

private struct FollowInsert: Encodable {
    var follower_id: UUID
    var followee_id: UUID
}

private struct RestaurantRow: Decodable {
    var id: UUID
    var provider: String
    var provider_place_id: String
    var lat: Double?
    var lng: Double?
    var location_cached_at: Date?

    var model: RestaurantRef {
        RestaurantRef(id: id, provider: provider, providerPlaceID: provider_place_id,
                      cachedCoordinate: lat.flatMap { lat in lng.map { Coordinate(latitude: lat, longitude: $0) } },
                      coordinateCachedAt: location_cached_at)
    }
}

private struct EnsureRestaurantParams: Encodable {
    var p_provider: String
    var p_place_id: String
    var p_lat: Double?
    var p_lng: Double?
}

private struct CacheLocationParams: Encodable {
    var p_restaurant_id: UUID
    var p_lat: Double
    var p_lng: Double
}

private struct SavedRow: Decodable {
    var restaurant_id: UUID
    var created_at: Date
}

private struct SavedInsert: Encodable {
    var user_id: UUID
    var restaurant_id: UUID
}

private struct SystemRow: Decodable {
    static let columns = "id,owner_id,template_key,forked_from_system_id,name,description,is_archived,current_version_id,created_at,updated_at"
    // Two foreign keys link systems and versions, so the embed names the one to follow.
    static let columnsWithDefinitions = columns
        + ",ranking_system_drafts(definition)"
        + ",ranking_system_versions!ranking_system_versions_system_id_fkey(\(VersionRow.columns))"

    var id: UUID
    var owner_id: UUID?
    var template_key: String?
    var forked_from_system_id: UUID?
    var name: String
    var description: String
    var is_archived: Bool
    var current_version_id: UUID?
    var created_at: Date
    var updated_at: Date
    var ranking_system_drafts: OneOrMany<DraftRow>?
    var ranking_system_versions: [VersionRow]?

    var model: RankingSystem {
        RankingSystem(id: id, ownerID: owner_id, templateKey: template_key, forkedFromSystemID: forked_from_system_id,
                      name: name, summary: description, isArchived: is_archived, currentVersionID: current_version_id,
                      draft: ranking_system_drafts?.values.first?.definition, createdAt: created_at, updatedAt: updated_at)
    }
}

private struct DraftRow: Decodable {
    var definition: SystemDraft
}

private struct DraftUpsert: Encodable {
    var system_id: UUID
    var definition: SystemDraft
    var updated_at: Date
}

private struct SystemInsert: Encodable {
    var id: UUID
    var owner_id: UUID
    var template_key: String?
    var forked_from_system_id: UUID?
    var name: String
    var description: String
}

private struct SystemNameUpdate: Encodable {
    var name: String
    var description: String
}

private struct VersionRow: Decodable {
    static let columns = "id,system_id,version_number,published_at,"
        + "ranking_criteria(id,position,name,guidance,max_points,criterion_score_levels(points,label,description))"

    var id: UUID
    var system_id: UUID
    var version_number: Int
    var published_at: Date
    var ranking_criteria: [CriterionRow]

    var model: SystemVersion {
        SystemVersion(id: id, systemID: system_id, number: version_number,
                      criteria: ranking_criteria.sorted { $0.position < $1.position }.map(\.model),
                      publishedAt: published_at)
    }
}

private struct CriterionRow: Decodable {
    var id: UUID
    var position: Int
    var name: String
    var guidance: String
    var max_points: Int
    var criterion_score_levels: [LevelRow]

    var model: Criterion {
        Criterion(id: id, name: name, guidance: guidance, maxPoints: max_points,
                  levels: criterion_score_levels.sorted { $0.points < $1.points }
                      .map { ScoreLevel(points: $0.points, label: $0.label, detail: $0.description) })
    }
}

private struct LevelRow: Decodable {
    var points: Int
    var label: String
    var description: String
}

private struct PublishParams: Encodable {
    var p_system_id: UUID
    var p_name: String
    var p_description: String
    var p_criteria: [CriterionPayload]
}

private struct CriterionPayload: Encodable {
    var name: String
    var guidance: String
    var max_points: Int
    var levels: [LevelPayload]
}

private struct LevelPayload: Encodable {
    var points: Int
    var label: String
    var description: String
}

private struct VisitRow: Decodable {
    static let columns = "id,user_id,restaurant_id,visited_on,notes,dishes,spend_per_person,currency_code,visibility,created_at,updated_at,"
        + "rating_revisions(id,visit_id,system_version_id,state,total,created_at,completed_at,"
        + "criterion_scores(criterion_id,score),ranking_system_versions(system_id)),"
        + "visit_photos(id,storage_path)"

    var id: UUID
    var user_id: UUID
    var restaurant_id: UUID
    var visited_on: String
    var notes: String
    var dishes: [String]
    var spend_per_person: Decimal?
    var currency_code: String
    var visibility: Visibility
    var created_at: Date
    var updated_at: Date
    var rating_revisions: [RevisionRow]?
    var visit_photos: [PhotoRow]?

    var model: Visit {
        Visit(id: id, userID: user_id, restaurantID: restaurant_id,
              visitedOn: DayFormat.date(from: visited_on) ?? created_at,
              notes: notes, dishes: dishes, spendPerPerson: spend_per_person, currencyCode: currency_code,
              visibility: visibility,
              photos: (visit_photos ?? []).map { VisitPhoto(id: $0.id, storagePath: $0.storage_path) },
              revisions: (rating_revisions ?? []).map(\.model),
              createdAt: created_at, updatedAt: updated_at)
    }
}

private struct RevisionRow: Decodable {
    struct ScoreRow: Decodable {
        var criterion_id: UUID
        var score: Int
    }

    struct VersionRef: Decodable {
        var system_id: UUID
    }

    var id: UUID
    var visit_id: UUID
    var system_version_id: UUID
    var state: RevisionState
    var total: Int?
    var created_at: Date
    var completed_at: Date?
    var criterion_scores: [ScoreRow]?
    var ranking_system_versions: VersionRef?

    var model: RatingRevision {
        RatingRevision(id: id, visitID: visit_id,
                       // Hidden only if the definition is unreadable, which the policies prevent
                       // for any rating the caller can see.
                       systemID: ranking_system_versions?.system_id ?? system_version_id,
                       versionID: system_version_id,
                       scores: Dictionary((criterion_scores ?? []).map { ($0.criterion_id, $0.score) }, uniquingKeysWith: { $1 }),
                       state: state, createdAt: created_at, completedAt: completed_at, total: total)
    }
}

private struct PhotoRow: Decodable {
    var id: UUID
    var storage_path: String
}

private struct PhotoInsert: Encodable {
    var visit_id: UUID
    var user_id: UUID
    var storage_path: String
}

private struct VisitWrite: Encodable {
    var user_id: UUID?
    var restaurant_id: UUID?
    var visited_on: String
    var notes: String
    var dishes: [String]
    var spend_per_person: Decimal?
    var currency_code: String
    var visibility: Visibility

    init(user_id: UUID?, restaurant_id: UUID?, details: VisitDetails) {
        self.user_id = user_id
        self.restaurant_id = restaurant_id
        visited_on = DayFormat.string(from: details.visitedOn)
        notes = details.notes.trimmed
        dishes = details.dishes.map(\.trimmed).filter { !$0.isEmpty }
        spend_per_person = details.spendPerPerson
        currency_code = details.currencyCode.uppercased()
        visibility = details.visibility
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Owner and restaurant are only sent on insert; an update must not try to move a visit.
        try container.encodeIfPresent(user_id, forKey: .user_id)
        try container.encodeIfPresent(restaurant_id, forKey: .restaurant_id)
        try container.encode(visited_on, forKey: .visited_on)
        try container.encode(notes, forKey: .notes)
        try container.encode(dishes, forKey: .dishes)
        try container.encode(spend_per_person, forKey: .spend_per_person) // explicit null clears it
        try container.encode(currency_code, forKey: .currency_code)
        try container.encode(visibility, forKey: .visibility)
    }

    enum CodingKeys: String, CodingKey {
        case user_id, restaurant_id, visited_on, notes, dishes, spend_per_person, currency_code, visibility
    }
}

private struct SaveRatingParams: Encodable {
    var p_visit_id: UUID
    var p_system_version_id: UUID
    var p_scores: [String: Int]
    var p_complete: Bool
}

private struct CommunityRow: Decodable {
    struct CriterionRow: Decodable {
        var criterion_id: UUID
        var average: Double?
    }

    var system_id: UUID
    var system_name: String
    var version_id: UUID
    var version_number: Int
    var user_count: Int
    var average: Double
    var criteria: [CriterionRow]
}

/// PostgREST returns a to-one embed as an object and a to-many embed as an array.
private struct OneOrMany<Element: Decodable>: Decodable {
    var values: [Element]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let many = try? container.decode([Element].self) {
            values = many
        } else {
            values = [try container.decode(Element.self)]
        }
    }
}

/// `visited_on` is a calendar date, not an instant, so it is sent and read as yyyy-MM-dd
/// in the device's calendar rather than converted through UTC.
private enum DayFormat {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func string(from date: Date) -> String { formatter.string(from: date) }
    static func date(from string: String) -> Date? { formatter.date(from: string) }
}
