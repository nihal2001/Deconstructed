import Foundation
import Observation

enum PlacesRequestKind: String, CaseIterable, Codable, Identifiable {
    case autocomplete
    case textSearch
    case nearbySearch
    case detailsLocation
    case detailsCore
    case detailsExtended

    var id: String { rawValue }

    var title: String {
        switch self {
        case .autocomplete: "Autocomplete"
        case .textSearch: "Text search"
        case .nearbySearch: "Search this area"
        case .detailsLocation: "Place details · location"
        case .detailsCore: "Place details · name and address"
        case .detailsExtended: "Place details · hours and contact"
        }
    }

    /// The Google billing SKU this request maps to. See docs/google-api-usage.md.
    var sku: String {
        switch self {
        case .autocomplete: "Autocomplete Requests (free inside a completed session)"
        case .textSearch: "Text Search Pro"
        case .nearbySearch: "Nearby Search Pro"
        case .detailsLocation: "Place Details Essentials"
        case .detailsCore: "Place Details Pro"
        case .detailsExtended: "Place Details Enterprise"
        }
    }
}

/// Counts every provider request and enforces this device's own per-minute and per-day caps
/// before anything is sent. It is a guard rail, not a replacement for quotas set in Google
/// Cloud Console: a client-side limit can always be bypassed by a modified app.
@MainActor
@Observable
final class RequestMonitor {
    struct Limits: Equatable {
        var perMinute: Int
        var perDay: Int
    }

    var limits: Limits
    private(set) var todayCounts: [PlacesRequestKind: Int] = [:]
    private(set) var blockedToday = 0
    private(set) var lastProviderError: String?

    @ObservationIgnored private var recent: [Date] = []
    @ObservationIgnored private var dayKey: String
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let now: () -> Date

    var todayTotal: Int { todayCounts.values.reduce(0, +) }

    init(limits: Limits, defaults: UserDefaults? = .standard, now: @escaping () -> Date = Date.init) {
        self.limits = limits
        self.defaults = defaults
        self.now = now
        dayKey = Self.key(for: now())
        load()
    }

    /// Call immediately before sending. Throws instead of sending when a cap is reached.
    func willSend(_ kind: PlacesRequestKind) throws {
        rollDayIfNeeded()
        let current = now()
        recent.removeAll { current.timeIntervalSince($0) >= 60 }

        if todayTotal >= limits.perDay {
            blockedToday += 1
            save()
            let tomorrow = Calendar.current.startOfDay(for: current).addingTimeInterval(86_400)
            throw PlacesError.localLimitReached(retryAfter: tomorrow.timeIntervalSince(current))
        }
        if recent.count >= limits.perMinute, let oldest = recent.first {
            blockedToday += 1
            save()
            throw PlacesError.localLimitReached(retryAfter: max(1, 60 - current.timeIntervalSince(oldest)))
        }

        recent.append(current)
        todayCounts[kind, default: 0] += 1
        save()
    }

    func recordProviderError(_ error: Error) {
        lastProviderError = error.localizedDescription
    }

    func resetCounts() {
        todayCounts = [:]
        blockedToday = 0
        recent = []
        lastProviderError = nil
        save()
    }

    private func rollDayIfNeeded() {
        let key = Self.key(for: now())
        guard key != dayKey else { return }
        dayKey = key
        todayCounts = [:]
        blockedToday = 0
    }

    private static func key(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "places-usage-\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    private func load() {
        guard let stored = defaults?.dictionary(forKey: dayKey) as? [String: Int] else { return }
        blockedToday = stored["blocked"] ?? 0
        for kind in PlacesRequestKind.allCases {
            if let count = stored[kind.rawValue] { todayCounts[kind] = count }
        }
    }

    private func save() {
        var stored = Dictionary(uniqueKeysWithValues: todayCounts.map { ($0.key.rawValue, $0.value) })
        stored["blocked"] = blockedToday
        defaults?.set(stored, forKey: dayKey)
    }
}

/// Wraps any provider so every request is counted and capped in one place.
@MainActor
final class MeteredPlacesProvider: PlacesProvider {
    private let base: PlacesProvider
    let monitor: RequestMonitor

    var providerKey: String { base.providerKey }
    var isDemo: Bool { base.isDemo }

    init(base: PlacesProvider, monitor: RequestMonitor) {
        self.base = base
        self.monitor = monitor
    }

    func autocomplete(query: String, near: Coordinate?, session: PlacesSession) async throws -> [PlaceSuggestion] {
        try await metered(.autocomplete) { try await self.base.autocomplete(query: query, near: near, session: session) }
    }

    func searchText(_ query: String, near: Coordinate?) async throws -> [Place] {
        try await metered(.textSearch) { try await self.base.searchText(query, near: near) }
    }

    func searchNearby(center: Coordinate, radiusMeters: Double) async throws -> [Place] {
        try await metered(.nearbySearch) { try await self.base.searchNearby(center: center, radiusMeters: radiusMeters) }
    }

    func details(placeID: String, level: PlaceDetailLevel, session: PlacesSession?) async throws -> Place {
        let kind: PlacesRequestKind = switch level {
        case .location: .detailsLocation
        case .core: .detailsCore
        case .extended: .detailsExtended
        }
        return try await metered(kind) { try await self.base.details(placeID: placeID, level: level, session: session) }
    }

    private func metered<T>(_ kind: PlacesRequestKind, _ send: () async throws -> T) async throws -> T {
        try monitor.willSend(kind)
        do {
            return try await send()
        } catch {
            monitor.recordProviderError(error)
            throw error
        }
    }
}
