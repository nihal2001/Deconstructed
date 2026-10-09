import Foundation
import Observation

/// Search state shared by the Discover and Map tabs.
///
/// Cost rules live here so they hold wherever search is triggered from:
/// - Autocomplete waits for a pause in typing and a minimum query length.
/// - One session token covers a run of keystrokes and is closed by the details request made
///   when a suggestion is picked. A new token is created for the next run.
/// - Nearby search only ever runs from `searchArea`, which is called by an explicit button.
///   Moving the map calls `mapMoved`, which records the area and sends nothing.
@MainActor
@Observable
final class DiscoveryModel {
    enum ResultSource: Equatable {
        case text(String)
        case area
    }

    struct MapArea: Equatable {
        var center: Coordinate
        var radiusMeters: Double
    }

    var query = ""
    private(set) var suggestions: [PlaceSuggestion] = []
    private(set) var results: [Place] = []
    private(set) var resultSource: ResultSource?
    private(set) var isSearching = false
    private(set) var isSuggesting = false
    private(set) var error: PlacesError?
    /// The area currently on screen in the Map tab. Never searched until the user asks.
    private(set) var visibleMapArea: MapArea?
    /// True once the map has moved away from the area the current results cover.
    private(set) var mapMovedSinceSearch = false

    @ObservationIgnored var onResults: ([Place]) -> Void = { _ in }
    @ObservationIgnored private let provider: PlacesProvider
    @ObservationIgnored private let minCharacters: Int
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var session: PlacesSession?
    @ObservationIgnored private var suggestTask: Task<Void, Never>?
    @ObservationIgnored private var lastAction: (() async -> Void)?
    /// Where the map was when results were last loaded (or when it first appeared).
    @ObservationIgnored private var anchorArea: MapArea?

    var minimumQueryLength: Int { minCharacters }
    var canRetry: Bool { error?.isRetryable == true && lastAction != nil }

    init(provider: PlacesProvider, config: AppConfig) {
        self.provider = provider
        minCharacters = config.autocompleteMinCharacters
        debounce = config.autocompleteDebounce
    }

    func reset() {
        suggestTask?.cancel()
        query = ""
        suggestions = []
        results = []
        resultSource = nil
        error = nil
        session = nil
    }

    // MARK: Autocomplete

    /// Call on every change to the search text. Sends at most one request per typing pause.
    func queryChanged(near origin: Coordinate?) {
        suggestTask?.cancel()
        let text = query.trimmed
        guard text.count >= minCharacters else {
            suggestions = []
            isSuggesting = false
            // Clearing the field abandons the session; the next one gets a fresh token.
            if text.isEmpty { session = nil }
            return
        }
        suggestTask = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self.loadSuggestions(for: text, near: origin)
        }
    }

    private func loadSuggestions(for text: String, near origin: Coordinate?) async {
        let session = session ?? PlacesSession()
        self.session = session
        isSuggesting = true
        defer { isSuggesting = false }
        do {
            let loaded = try await provider.autocomplete(query: text, near: origin, session: session)
            guard !Task.isCancelled, query.trimmed == text else { return }
            suggestions = loaded
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            suggestions = []
            self.error = (error as? PlacesError) ?? .other(error.localizedDescription)
            lastAction = { [weak self] in await self?.loadSuggestions(for: text, near: origin) }
        }
    }

    /// Hands over the open session so the details request can close it, and forgets it here
    /// so it is never reused.
    func takeSessionForSelection() -> PlacesSession? {
        suggestTask?.cancel()
        defer { session = nil }
        suggestions = []
        return session
    }

    // MARK: Searches

    func searchText(near origin: Coordinate?) async {
        let text = query.trimmed
        guard !text.isEmpty else { return }
        suggestTask?.cancel()
        suggestions = []
        session = nil // A full search is its own request, not part of the autocomplete session.
        await run(source: .text(text)) { [provider] in try await provider.searchText(text, near: origin) }
    }

    /// The only entry point for nearby discovery. Bound to the "Search this area" button.
    func searchArea(center: Coordinate, radiusMeters: Double) async {
        let radius = min(max(radiusMeters, 300), 5_000)
        visibleMapArea = visibleMapArea ?? MapArea(center: center, radiusMeters: radius)
        anchorArea = MapArea(center: center, radiusMeters: radiusMeters)
        await run(source: .area) { [provider] in try await provider.searchNearby(center: center, radiusMeters: radius) }
        mapMovedSinceSearch = false
    }

    /// Records where the map is looking. Deliberately performs no request.
    func mapMoved(center: Coordinate, radiusMeters: Double) {
        let area = MapArea(center: center, radiusMeters: radiusMeters)
        visibleMapArea = area
        guard let anchor = anchorArea else {
            anchorArea = area
            return
        }
        let panned = anchor.center.distance(to: center) > max(150, anchor.radiusMeters * 0.3)
        let zoomed = radiusMeters > anchor.radiusMeters * 1.6 || radiusMeters < anchor.radiusMeters / 1.6
        mapMovedSinceSearch = panned || zoomed
    }

    func clearResults() {
        results = []
        resultSource = nil
        error = nil
    }

    func retry() async {
        await lastAction?()
    }

    private func run(source: ResultSource, _ search: @escaping () async throws -> [Place]) async {
        isSearching = true
        error = nil
        defer { isSearching = false }
        do {
            let loaded = try await search()
            results = loaded
            resultSource = source
            onResults(loaded)
        } catch {
            self.error = (error as? PlacesError) ?? .other(error.localizedDescription)
            lastAction = { [weak self] in await self?.run(source: source, search) }
        }
    }
}
