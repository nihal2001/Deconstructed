import SwiftUI

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()
    @State private var showAreaPicker = false
    @State private var openingSuggestionID: String?

    private var discovery: DiscoveryModel { model.discovery }
    private var origin: Coordinate? { model.location.searchOrigin }

    var body: some View {
        @Bindable var discovery = model.discovery
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    areaRow

                    if let error = discovery.error {
                        ErrorBanner(message: error.localizedDescription,
                                    retry: discovery.canRetry ? { Task { await discovery.retry() } } : nil)
                    }

                    if !discovery.suggestions.isEmpty {
                        suggestionList
                    } else if discovery.isSearching {
                        ProgressView("Searching…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if discovery.resultSource != nil {
                        resultList
                    } else {
                        landing
                    }
                }
                .padding(Theme.spacing)
            }
            .screenBackground()
            .navigationTitle("Discover")
            .searchable(text: $discovery.query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Restaurant, cuisine or neighbourhood")
            .onSubmit(of: .search) {
                Task { await discovery.searchText(near: origin) }
            }
            .onChange(of: discovery.query) {
                discovery.queryChanged(near: origin)
            }
            .appRoutes()
            .sheet(isPresented: $showAreaPicker) { AreaPickerSheet() }
        }
    }

    // MARK: Sections

    private var areaRow: some View {
        HStack(spacing: 10) {
            Image(systemName: model.location.manualArea == nil ? "location.fill" : "mappin.and.ellipse")
                .foregroundStyle(Theme.seagrass)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Searching near").font(.caption).foregroundStyle(Theme.inkSoft)
                Text(model.location.originLabel).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            Spacer()
            Button("Change") { showAreaPicker = true }
                .font(.subheadline.weight(.semibold))
        }
        .card(padding: 12)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens area options")
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(discovery.suggestions) { suggestion in
                Button {
                    open(suggestion)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "fork.knife").foregroundStyle(Theme.inkSoft).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            if let subtitle = suggestion.subtitle {
                                Text(subtitle).font(.footnote).foregroundStyle(Theme.inkSoft).lineLimit(1)
                            }
                        }
                        Spacer()
                        if openingSuggestionID == suggestion.id {
                            ProgressView()
                        } else if suggestion.isDemo {
                            DemoBadge()
                        }
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if suggestion.id != discovery.suggestions.last?.id { Divider() }
            }
            Divider()
            Button {
                Task { await discovery.searchText(near: origin) }
            } label: {
                Label("See all results for “\(discovery.query.trimmed)”", systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 10)
            }
            ProviderAttribution(isDemo: discovery.suggestions.first?.isDemo ?? model.isDemo)
                .padding(.top, 4)
        }
        .card(padding: 14)
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(resultTitle, detail: discovery.results.isEmpty ? nil : "\(discovery.results.count) found")
                Button("Clear") { discovery.clearResults() }.font(.subheadline.weight(.semibold))
            }
            if discovery.results.isEmpty {
                EmptyState(symbol: "fork.knife", title: "Nothing found",
                           message: model.isDemo
                               ? "The demo only knows about its own invented restaurants. Try “tacos”, “Mission” or “ramen”."
                               : "Try a different name, or widen the area.")
                    .card()
            } else {
                ForEach(discovery.results) { place in
                    NavigationLink(value: Route.restaurant(placeID: place.placeID)) {
                        PlaceRow(place: place)
                    }
                    .buttonStyle(.plain)
                }
                ProviderAttribution(isDemo: discovery.results.first?.isDemo ?? model.isDemo)
            }
        }
    }

    private var resultTitle: String {
        switch discovery.resultSource {
        case .text(let query): "Results for “\(query)”"
        case .area: "In this area"
        case nil: ""
        }
    }

    private var landing: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Find somewhere to eat")
                    .font(.display(.title2))
                    .foregroundStyle(Theme.ink)
                Text("Search by name above, or look at what's around the area you've chosen. Nearby search only runs when you ask for it.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                Button {
                    searchArea()
                } label: {
                    Label("Search this area", systemImage: "scope")
                }
                .buttonStyle(.primary)
            }
            .hero()

            let wantToTry = model.saved.sorted { $0.savedAt > $1.savedAt }.prefix(4)
            if !wantToTry.isEmpty {
                SectionTitle("Want to try", detail: "From your saved places")
                ForEach(Array(wantToTry), id: \.restaurantID) { saved in
                    if let ref = model.restaurants[saved.restaurantID] {
                        NavigationLink(value: Route.restaurant(placeID: ref.providerPlaceID)) {
                            SavedRestaurantRow(restaurantID: ref.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func searchArea() {
        guard let origin else {
            showAreaPicker = true
            return
        }
        Task { await discovery.searchArea(center: origin, radiusMeters: 1_500) }
    }

    private func open(_ suggestion: PlaceSuggestion) {
        guard openingSuggestionID == nil else { return }
        openingSuggestionID = suggestion.id
        // Picking a suggestion ends the autocomplete session: the details request carries its token.
        let session = discovery.takeSessionForSelection()
        Task {
            await model.ensurePlace(suggestion.placeID, level: .core, session: session)
            openingSuggestionID = nil
            path.append(Route.restaurant(placeID: suggestion.placeID))
        }
    }
}

/// A search result. Shows what the search already returned, so opening it costs nothing more.
struct PlaceRow: View {
    @Environment(AppModel.self) private var model
    var place: Place

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(place.name ?? "Restaurant")
                        .font(.display(.headline))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    if place.isDemo { DemoBadge() }
                }
                if !place.subtitle.isEmpty {
                    Text(place.subtitle).font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
                if let address = place.address {
                    Text(address).font(.footnote).foregroundStyle(Theme.inkSoft).lineLimit(2).multilineTextAlignment(.leading)
                }
                PlaceStatusTags(placeID: place.placeID)
            }
            Spacer(minLength: 4)
            SaveButton(place: place)
        }
        .card(padding: 14)
        .accessibilityElement(children: .contain)
    }
}

/// "Visited · 8/10 · General" or "Want to try", from the user's own data.
struct PlaceStatusTags: View {
    @Environment(AppModel.self) private var model
    var placeID: String

    var body: some View {
        let latest = model.visits(forPlaceID: placeID).first(where: \.isCompleted)?.activeRevision
        HStack(spacing: 6) {
            if let latest {
                Tag(text: "Visited · \(model.ratingLabel(latest))", symbol: "checkmark", tone: .seagrass, solid: true)
            } else if model.isSaved(placeID: placeID) {
                Tag(text: "Want to try", symbol: "bookmark.fill", tone: .olive, solid: true)
            }
        }
    }
}

struct SaveButton: View {
    @Environment(AppModel.self) private var model
    var place: Place

    var body: some View {
        let isSaved = model.isSaved(placeID: place.placeID)
        AsyncButton {
            try await model.setSaved(place, saved: !isSaved)
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.title3)
                .foregroundStyle(isSaved ? Theme.olive : Theme.inkSoft)
                .frame(width: 44, height: 44)
                .background(isSaved ? Theme.olive.opacity(0.18) : Theme.fill, in: Circle())
                .symbolEffect(.bounce, value: isSaved)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved ? "Remove from Want to try" : "Save to Want to try")
    }
}

/// A row for a restaurant the app only knows by ID. Its name is fetched on demand and kept
/// in memory, never stored.
struct SavedRestaurantRow: View {
    @Environment(AppModel.self) private var model
    var restaurantID: UUID
    var trailing: AnyView?

    var body: some View {
        let place = model.place(for: restaurantID)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(model.displayName(for: restaurantID))
                        .font(.display(.headline))
                        .foregroundStyle(Theme.ink)
                        .redacted(reason: place?.name == nil && model.placeLoadError == nil ? .placeholder : [])
                    if place?.isDemo == true { DemoBadge() }
                }
                if let subtitle = place?.subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer(minLength: 4)
            if let trailing { trailing } else {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSoft)
            }
        }
        .card(padding: 14)
        .task(id: model.placeReloadToken) { await model.ensurePlace(for: restaurantID) }
    }
}

/// Required provider credit wherever listing content is shown.
struct ProviderAttribution: View {
    var isDemo: Bool
    var thirdParty: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isDemo {
                Text("Demo listings · invented for this demo, not real search results")
            } else {
                // Google's guidelines: the words "Google Maps", unstyled by the app's brand.
                Text("Google Maps")
                    .font(.system(.footnote, design: .default).weight(.medium))
                    .foregroundStyle(Color(light: 0x5E5E5E, dark: 0xFFFFFF))
                    .accessibilityLabel("Listing information from Google Maps")
                if let thirdParty, !thirdParty.isBlank { Text(thirdParty) }
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.inkSoft)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
