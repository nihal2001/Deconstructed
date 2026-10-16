import SwiftUI

struct MapScreen: View {
    @Environment(AppModel.self) private var model

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case wantToTry = "Want to try"
        case visited = "Visited"

        var id: String { rawValue }
    }

    @State private var filter: Filter = .all
    @State private var selection: String?
    @State private var camera: MapCameraRequest?
    /// Coordinates resolved for saved and visited places, by restaurant ID.
    @State private var coordinates: [UUID: Coordinate] = [:]
    @State private var showAreaPicker = false
    @State private var path = NavigationPath()
    /// How much of the map the controls and the preview card cover, measured so the map can
    /// keep the Google logo and the selected pin clear of them at any text size.
    @State private var controlsHeight: CGFloat = 0
    @State private var cardHeight: CGFloat = 0

    private var discovery: DiscoveryModel { model.discovery }
    private var location: LocationService { model.location }

    private var pins: [MapPin] {
        var pins: [MapPin] = []
        var used = Set<String>()
        let visited = model.visitedRestaurantIDs

        func add(_ restaurantID: UUID, kind: MapPin.Kind) {
            guard let ref = model.restaurants[restaurantID], let coordinate = coordinates[restaurantID],
                  used.insert(ref.providerPlaceID).inserted else { return }
            pins.append(MapPin(id: ref.providerPlaceID, coordinate: coordinate, kind: kind))
        }

        if filter != .wantToTry {
            visited.forEach { add($0, kind: .visited) }
        }
        if filter != .visited {
            model.saved.map(\.restaurantID).filter { !visited.contains($0) }.forEach { add($0, kind: .wantToTry) }
        }
        if filter == .all {
            for place in discovery.results {
                guard let coordinate = place.coordinate, used.insert(place.placeID).inserted else { continue }
                pins.append(MapPin(id: place.placeID, coordinate: coordinate, kind: .result))
            }
            // A place opened with "View on map" that is neither saved nor in the results.
            if let focus = model.mapFocusPlaceID ?? selection, !used.contains(focus),
               let coordinate = model.places[focus]?.coordinate {
                pins.append(MapPin(id: focus, coordinate: coordinate, kind: .result))
            }
        }
        return pins
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                RestaurantMap(
                    usesGoogle: !model.isDemo, pins: pins, selection: $selection, camera: camera,
                    showsUserLocation: location.access == .granted,
                    topInset: controlsHeight, bottomInset: selection == nil ? 0 : cardHeight,
                    onMove: { center, radius in discovery.mapMoved(center: center, radiusMeters: radius) })
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 10) {
                    controls
                    if let error = discovery.error {
                        ErrorBanner(message: error.localizedDescription,
                                    retry: discovery.canRetry ? { Task { await discovery.retry() } } : nil)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .environment(\.colorScheme, .light)
                    }
                    if location.access == .denied, location.manualArea == nil {
                        locationOffBanner
                    }
                    if camera == nil {
                        needsAreaPrompt
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
            }
            .safeAreaInset(edge: .bottom) {
                if let selection {
                    MapPreviewCard(placeID: selection) { self.selection = nil }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: selection)
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.jet, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .appRoutes()
            .sheet(isPresented: $showAreaPicker) { AreaPickerSheet() }
            .task(id: pinSourceKey) { await resolveCoordinates() }
            .onAppear(perform: setInitialCamera)
            .onChange(of: location.searchOrigin) { _, origin in
                if let origin { camera = MapCameraRequest(center: origin, radiusMeters: 2_200) }
            }
            .onChange(of: model.mapFocusPlaceID, initial: true) { _, placeID in
                focus(on: placeID)
            }
        }
    }

    // MARK: Overlays

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Filter pins")

                Button {
                    recenter()
                } label: {
                    Image(systemName: location.manualArea == nil ? "location.fill" : "mappin.and.ellipse")
                        .frame(width: 40, height: 32)
                }
                .buttonStyle(.bordered)
                .contextMenu {
                    Button("Change area", systemImage: "mappin.and.ellipse") { showAreaPicker = true }
                }
                .accessibilityLabel("Centre on \(location.originLabel)")
                .accessibilityHint("Touch and hold to change the area")
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Nearby search costs money per request, so it only ever runs from this button.
            Button {
                searchThisArea()
            } label: {
                HStack(spacing: 6) {
                    if discovery.isSearching { ProgressView().controlSize(.small) } else { Image(systemName: "scope") }
                    Text("Search this area")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .foregroundStyle(emphasiseSearch ? Theme.alabaster : Theme.ink)
                .background(emphasiseSearch ? AnyShapeStyle(Theme.rose) : AnyShapeStyle(.regularMaterial), in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            }
            .disabled(discovery.isSearching || discovery.visibleMapArea == nil)
            .animation(.snappy, value: emphasiseSearch)

            if discovery.resultSource != nil, filter == .all {
                HStack(spacing: 8) {
                    Text("\(discovery.results.count) result\(discovery.results.count == 1 ? "" : "s") on the map")
                    Button("Clear") { discovery.clearResults() }.fontWeight(.semibold)
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
            }
        }
    }

    private var emphasiseSearch: Bool {
        discovery.mapMovedSinceSearch || discovery.resultSource == nil
    }

    private var locationOffBanner: some View {
        Button {
            showAreaPicker = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "location.slash").foregroundStyle(Theme.warning)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Location is off").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text("Set an area by hand to centre the map.").font(.footnote).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Text("Set area").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.rose)
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .environment(\.colorScheme, .light)
        }
        .buttonStyle(.plain)
    }

    private var needsAreaPrompt: some View {
        VStack(spacing: 10) {
            Text("Where should the map look?")
                .font(.display(.headline)).foregroundStyle(Theme.ink)
            Text("Share your location or set an area by hand. Your saved places appear either way.")
                .font(.footnote).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
            Button("Choose an area") { showAreaPicker = true }.buttonStyle(.primary)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .environment(\.colorScheme, .light)
        .padding(.top, 40)
    }

    // MARK: Actions

    /// Changes whenever the set of saved or visited places does.
    private var pinSourceKey: [UUID] {
        (model.saved.map(\.restaurantID) + Array(model.visitedRestaurantIDs)).sorted { $0.uuidString < $1.uuidString }
    }

    /// Finds a coordinate for each saved or visited place. This uses the short-lived stored
    /// coordinate where there is one, and otherwise a location-only details request.
    private func resolveCoordinates() async {
        for id in pinSourceKey where coordinates[id] == nil {
            guard let ref = model.restaurants[id] else { continue }
            if let coordinate = await model.pinCoordinate(for: ref) { coordinates[id] = coordinate }
        }
    }

    private func setInitialCamera() {
        guard camera == nil else { return }
        if let origin = location.searchOrigin ?? (model.isDemo ? DemoCatalog.home : nil) {
            camera = MapCameraRequest(center: origin, radiusMeters: model.isDemo && location.searchOrigin == nil ? 5_500 : 2_200)
        } else if location.access == .notDetermined {
            location.requestAccess()
        }
    }

    private func recenter() {
        if let origin = location.searchOrigin {
            camera = MapCameraRequest(center: origin, radiusMeters: 2_200)
        } else if location.access == .notDetermined {
            location.requestAccess()
        } else {
            showAreaPicker = true
        }
    }

    private func searchThisArea() {
        guard let area = discovery.visibleMapArea else { return }
        filter = .all
        selection = nil
        Task { await discovery.searchArea(center: area.center, radiusMeters: area.radiusMeters) }
    }

    private func focus(on placeID: String?) {
        guard let placeID else { return }
        filter = .all
        Task {
            let place = await model.ensurePlace(placeID, level: .location)
            if let coordinate = place?.coordinate {
                camera = MapCameraRequest(center: coordinate, radiusMeters: 700)
            }
            selection = placeID
            // Keep the focus pin alive through `selection`, then release the request.
            model.mapFocusPlaceID = nil
        }
    }
}

/// The card shown when a pin is tapped. The name is loaded now, on demand.
struct MapPreviewCard: View {
    @Environment(AppModel.self) private var model
    var placeID: String
    var close: () -> Void

    var body: some View {
        let place = model.places[placeID]
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(place?.name ?? (model.placeLoadError == nil ? "Loading…" : "Name unavailable"))
                            .font(.display(.title3))
                            .foregroundStyle(Theme.ink)
                        if place?.isDemo == true { DemoBadge() }
                    }
                    if let subtitle = place?.subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.subheadline).foregroundStyle(Theme.inkSoft)
                    }
                    PlaceStatusTags(placeID: placeID)
                }
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(Theme.inkSoft)
                }
                .accessibilityLabel("Close preview")
            }
            if let error = model.placeLoadError, place?.name == nil {
                ErrorBanner(message: error.localizedDescription, retry: error.isRetryable ? { model.retryPlaceLoads() } : nil)
            }
            HStack(spacing: 10) {
                NavigationLink(value: Route.restaurant(placeID: placeID)) {
                    Text("Open profile")
                }
                .buttonStyle(.primary)
                if let place { SaveButton(place: place) }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .environment(\.colorScheme, .light)
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .task(id: "\(placeID)-\(model.placeReloadToken)") {
            await model.ensurePlace(placeID, level: .core)
        }
    }
}
