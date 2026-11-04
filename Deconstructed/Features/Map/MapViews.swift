import GoogleMaps
import MapKit
import SwiftUI

struct MapPin: Identifiable, Hashable {
    enum Kind: Hashable {
        case wantToTry
        case visited
        case result
    }

    var id: String // provider place ID
    var coordinate: Coordinate
    var kind: Kind

    var color: UIColor {
        switch kind {
        case .wantToTry: UIColor(hex: Theme.ultramarineHex)
        case .visited: UIColor(hex: Theme.tealHex)
        case .result: UIColor(hex: Theme.tomatoHex)
        }
    }

    var symbol: String {
        switch kind {
        case .wantToTry: "bookmark.fill"
        case .visited: "checkmark"
        case .result: "fork.knife"
        }
    }
}

/// A one-off instruction to move the map. A new `id` means "do it again".
struct MapCameraRequest: Equatable {
    var id = UUID()
    var center: Coordinate
    var radiusMeters: Double
}

/// The map used by the Map tab. Google Places content must be shown on a Google map, so the
/// live app uses the Google Maps SDK. The demo has no API key and only fictional places, so
/// it uses Apple's map instead. Both report camera movement and never search on their own.
struct RestaurantMap: View {
    var usesGoogle: Bool
    var pins: [MapPin]
    @Binding var selection: String?
    var camera: MapCameraRequest?
    var showsUserLocation: Bool
    /// How far down from the top of the safe area the app's controls cover the map.
    var topInset: CGFloat
    /// How far up from the bottom safe area the preview card covers the map.
    var bottomInset: CGFloat
    var onMove: (Coordinate, Double, GeoBounds) -> Void
    /// A count marker was tapped: the place IDs it stands for.
    var onSelectGroup: ([String]) -> Void

    var body: some View {
        if usesGoogle {
            GoogleMapView(pins: pins, selection: $selection, camera: camera, showsUserLocation: showsUserLocation,
                          topInset: topInset, bottomInset: bottomInset, onMove: onMove, onSelectGroup: onSelectGroup)
        } else {
            AppleMapView(pins: pins, selection: $selection, camera: camera, showsUserLocation: showsUserLocation,
                         onMove: onMove, onSelectGroup: onSelectGroup)
        }
    }
}

// MARK: - Apple (demo)

struct AppleMapView: UIViewRepresentable {
    var pins: [MapPin]
    @Binding var selection: String?
    var camera: MapCameraRequest?
    var showsUserLocation: Bool
    var onMove: (Coordinate, Double, GeoBounds) -> Void
    /// A count marker was tapped: the place IDs it stands for.
    var onSelectGroup: ([String]) -> Void

    final class PinAnnotation: NSObject, MKAnnotation {
        let pin: MapPin
        var coordinate: CLLocationCoordinate2D { pin.coordinate.clLocation }
        init(pin: MapPin) { self.pin = pin }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        MapStyle.apply(to: map)
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "pin")
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        map.showsUserLocation = showsUserLocation

        let existing = map.annotations.compactMap { $0 as? PinAnnotation }
        let wanted = Set(pins)
        let stale = existing.filter { !wanted.contains($0.pin) }
        let present = Set(existing.map(\.pin))
        map.removeAnnotations(stale)
        map.addAnnotations(pins.filter { !present.contains($0) }.map(PinAnnotation.init))

        if let camera, camera.id != context.coordinator.lastCameraID {
            context.coordinator.lastCameraID = camera.id
            let region = MKCoordinateRegion(center: camera.center.clLocation,
                                            latitudinalMeters: camera.radiusMeters * 2, longitudinalMeters: camera.radiusMeters * 2)
            map.setRegion(region, animated: context.coordinator.hasSetCamera)
            context.coordinator.hasSetCamera = true
        }

        // Restyle the pins whose selected state changed. A tapped pin is restyled in place. A pin
        // chosen another way (from a group's cards) may be hidden inside a cluster, so it is re-added,
        // which draws it on its own in the selected style.
        let coordinator = context.coordinator
        if coordinator.styledSelection != selection {
            let changed = Set([coordinator.styledSelection, selection].compactMap { $0 })
            coordinator.styledSelection = selection
            var readd: [PinAnnotation] = []
            for annotation in map.annotations.compactMap({ $0 as? PinAnnotation }) where changed.contains(annotation.pin.id) {
                let isSelected = annotation.pin.id == selection
                let tapped = map.selectedAnnotations.contains { $0 === annotation }
                if let view = map.view(for: annotation) as? MKMarkerAnnotationView, !isSelected || tapped {
                    Coordinator.style(view, for: annotation.pin, selected: isSelected)
                } else {
                    readd.append(annotation)
                }
            }
            map.removeAnnotations(readd)
            map.addAnnotations(readd.map { PinAnnotation(pin: $0.pin) })
        }

        let selected = map.selectedAnnotations.compactMap { ($0 as? PinAnnotation)?.pin.id }.first
        if selection != selected {
            map.selectedAnnotations.forEach { map.deselectAnnotation($0, animated: true) }
            if let selection, let annotation = map.annotations.first(where: { ($0 as? PinAnnotation)?.pin.id == selection }) {
                map.selectAnnotation(annotation, animated: true)
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: AppleMapView
        var lastCameraID: UUID?
        var hasSetCamera = false
        /// The selection the pin views were last styled for.
        var styledSelection: String?

        init(_ parent: AppleMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: annotation) as? MKMarkerAnnotationView
                view?.markerTintColor = UIColor(hex: Theme.inkHex)
                view?.glyphTintColor = .white
                view?.glyphText = "\(cluster.memberAnnotations.count)"
                view?.accessibilityLabel = "\(cluster.memberAnnotations.count) restaurants. Double tap to see them."
                return view
            }
            guard let annotation = annotation as? PinAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "pin", for: annotation) as? MKMarkerAnnotationView
            view?.glyphImage = UIImage(systemName: annotation.pin.symbol)
            view?.accessibilityLabel = switch annotation.pin.kind {
            case .wantToTry: "Want to try"
            case .visited: "Visited"
            case .result: "Search result"
            }
            if let view { Self.style(view, for: annotation.pin, selected: annotation.pin.id == parent.selection) }
            return view
        }

        /// The selected pin is inverted (white with the symbol in the pin's colour), always shown,
        /// and kept out of clusters so it can't be hidden inside a count marker.
        static func style(_ view: MKMarkerAnnotationView, for pin: MapPin, selected: Bool) {
            view.markerTintColor = selected ? .white : pin.color
            view.glyphTintColor = selected ? pin.color : .white
            view.clusteringIdentifier = selected ? nil : "restaurant"
            view.displayPriority = selected || pin.kind != .result ? .required : .defaultHigh
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let wash = overlay as? MapStyle.Wash { return MapStyle.Wash.renderer(for: wash) }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let cluster = annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(annotation, animated: false)
                parent.onSelectGroup(cluster.memberAnnotations.compactMap { ($0 as? PinAnnotation)?.pin.id })
            } else if let pin = (annotation as? PinAnnotation)?.pin {
                parent.selection = pin.id
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect annotation: MKAnnotation) {
            if let pin = (annotation as? PinAnnotation)?.pin, parent.selection == pin.id {
                parent.selection = nil
            }
        }

        // Camera movement is reported, and that is all. Nothing is fetched from here.
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = mapView.region
            let radius = region.span.latitudeDelta * 111_000 / 2
            let bounds = GeoBounds(
                southWest: Coordinate(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                                      longitude: region.center.longitude - region.span.longitudeDelta / 2),
                northEast: Coordinate(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                                      longitude: region.center.longitude + region.span.longitudeDelta / 2))
            parent.onMove(Coordinate(region.center), radius, bounds)
        }
    }
}

// MARK: - Google (live)

struct GoogleMapView: UIViewRepresentable {
    var pins: [MapPin]
    @Binding var selection: String?
    var camera: MapCameraRequest?
    var showsUserLocation: Bool
    var topInset: CGFloat
    var bottomInset: CGFloat
    var onMove: (Coordinate, Double, GeoBounds) -> Void
    /// A count marker was tapped: the place IDs it stands for.
    var onSelectGroup: ([String]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GMSMapView {
        let map = GMSMapView(options: GMSMapViewOptions())
        map.delegate = context.coordinator
        MapStyle.apply(to: map)
        map.settings.rotateGestures = false
        map.settings.tiltGestures = false
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        map.isMyLocationEnabled = showsUserLocation
        // Keeps the Google logo and attribution clear of the preview card. Padding only the bottom
        // would re-centre the camera in the smaller area and move the map, so the top is padded by
        // the same amount. The centre stays put, and so does everything on screen.
        let padding = UIEdgeInsets(top: bottomInset, left: 0, bottom: bottomInset, right: 0)
        if map.padding != padding { map.padding = padding }

        if let camera, camera.id != coordinator.lastCameraID {
            coordinator.lastCameraID = camera.id
            let latDelta = camera.radiusMeters / 111_000
            let lngDelta = latDelta / max(0.2, cos(camera.center.latitude * .pi / 180))
            let bounds = GMSCoordinateBounds(
                coordinate: CLLocationCoordinate2D(latitude: camera.center.latitude + latDelta, longitude: camera.center.longitude + lngDelta),
                coordinate: CLLocationCoordinate2D(latitude: camera.center.latitude - latDelta, longitude: camera.center.longitude - lngDelta))
            let update = GMSCameraUpdate.fit(bounds, withPadding: 24)
            if coordinator.hasSetCamera {
                map.animate(with: update)
                coordinator.isFollowingRequest = true
            } else {
                map.moveCamera(update)
            }
            coordinator.hasSetCamera = true
        }

        // Compared as sets: the same pins can arrive in a different order after an unrelated update.
        if Set(coordinator.pins) != Set(pins) {
            coordinator.pins = pins
            coordinator.groups = nil
            coordinator.render(on: map)
        } else if coordinator.renderedSelection != selection {
            coordinator.render(on: map)
        }
        coordinator.revealSelection(on: map)
    }

    /// Draws markers and groups those that would overlap on screen into count markers.
    /// Groups are worked out once for each new set of pins, at the zoom of that moment, and then
    /// kept as the map moves, so zooming or panning never merges or splits them. No requests.
    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleMapView
        var pins: [MapPin] = []
        /// Nil until the pins have been grouped on a laid-out map.
        var groups: [[MapPin]]?
        var lastCameraID: UUID?
        var hasSetCamera = false
        var renderedSelection: String?
        /// True while the map animates to a camera request, which revealing the selection would cancel.
        var isFollowingRequest = false
        private var markers: [GMSMarker] = []
        /// One image per kind and state, shared by every marker that uses it.
        private var badges: [String: UIImage] = [:]
        private let cellSize: CGFloat = 56
        /// The selection and insets last revealed, so the map pans for a new selection or a
        /// resized card but never fights the user dragging the selected pin out of view.
        private var revealed: RevealState?

        private struct RevealState: Equatable {
            var placeID: String
            var top: CGFloat
            var bottom: CGFloat
        }

        init(_ parent: GoogleMapView) { self.parent = parent }

        /// Pans just enough to bring the selected marker out from under the controls and the card.
        func revealSelection(on map: GMSMapView) {
            guard let selection = parent.selection else {
                revealed = nil
                return
            }
            let state = RevealState(placeID: selection, top: parent.topInset, bottom: map.padding.bottom)
            guard state != revealed, hasSetCamera, !isFollowingRequest, !map.bounds.isEmpty,
                  let marker = markers.first(where: { ($0.userData as? [String]) == [selection] }) else { return }
            revealed = state

            let size = marker.iconView?.bounds.size ?? marker.icon?.size ?? .zero
            let markerTop = map.projection.point(for: marker.position).y - size.height * marker.groundAnchor.y
            let markerBottom = markerTop + size.height
            let margin: CGFloat = 8
            let clearTop = map.safeAreaInsets.top + state.top + margin
            let clearBottom = map.bounds.height - map.safeAreaInsets.bottom - state.bottom - margin
            // Clear of the card first, then of the controls if there is not room for both.
            var shift = max(0, markerBottom - clearBottom)
            if markerTop - shift < clearTop { shift = markerTop - clearTop }
            if shift != 0 { map.animate(with: GMSCameraUpdate.scrollBy(x: 0, y: shift)) }
        }

        func render(on map: GMSMapView) {
            // Before the first layout the projection is meaningless and screen points can't be
            // grouped. The camera settling afterwards calls back here.
            guard !map.bounds.isEmpty else { return }
            markers.forEach { $0.map = nil }
            markers = []
            renderedSelection = parent.selection

            if groups == nil {
                var cells: [String: [MapPin]] = [:]
                for pin in pins {
                    let point = map.projection.point(for: pin.coordinate.clLocation)
                    cells["\(Int((point.x / cellSize).rounded(.down))):\(Int((point.y / cellSize).rounded(.down)))", default: []].append(pin)
                }
                groups = Array(cells.values)
            }

            for group in groups ?? [] {
                let marker: GMSMarker
                if group.count == 1, let pin = group.first {
                    marker = pinMarker(for: pin)
                } else {
                    let lat = group.map(\.coordinate.latitude).reduce(0, +) / Double(group.count)
                    let lng = group.map(\.coordinate.longitude).reduce(0, +) / Double(group.count)
                    marker = GMSMarker(position: CLLocationCoordinate2D(latitude: lat, longitude: lng))
                    marker.iconView = Self.clusterView(count: group.count)
                    marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                    marker.userData = group.map(\.id)
                    marker.accessibilityLabel = "\(group.count) restaurants. Double tap to see them."
                }
                marker.map = map
                markers.append(marker)
            }
            // A selected pin inside a group is drawn on top of it, leaving the group as it was.
            if let selection = parent.selection,
               groups?.contains(where: { $0.count > 1 && $0.contains { $0.id == selection } }) == true,
               let pin = pins.first(where: { $0.id == selection }) {
                let marker = pinMarker(for: pin)
                marker.map = map
                markers.append(marker)
            }
        }

        private func pinMarker(for pin: MapPin) -> GMSMarker {
            let isSelected = pin.id == parent.selection
            let marker = GMSMarker(position: pin.coordinate.clLocation)
            marker.icon = badge(for: pin, selected: isSelected)
            marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
            marker.userData = [pin.id]
            marker.zIndex = isSelected ? 10 : 1
            let label = switch pin.kind {
            case .wantToTry: "Want to try"
            case .visited: "Visited"
            case .result: "Search result"
            }
            marker.accessibilityLabel = isSelected ? "\(label), selected" : label
            return marker
        }

        private func badge(for pin: MapPin, selected: Bool) -> UIImage {
            let key = "\(pin.kind)-\(selected)"
            if let badge = badges[key] { return badge }
            let badge = MapStyle.badge(for: pin, selected: selected)
            badges[key] = badge
            return badge
        }

        private static func clusterView(count: Int) -> UIView {
            let label = UILabel(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
            label.text = "\(count)"
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 15, weight: .bold)
            label.textColor = .white
            label.backgroundColor = UIColor(hex: Theme.inkHex)
            label.layer.cornerRadius = 20
            label.layer.borderWidth = 2
            label.layer.borderColor = UIColor.white.cgColor
            label.clipsToBounds = true
            return label
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard let ids = marker.userData as? [String] else { return false }
            if ids.count == 1 {
                parent.selection = ids[0]
            } else {
                parent.onSelectGroup(ids)
            }
            return true
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            parent.selection = nil
        }

        // Camera settled: regroup markers and report the new area. No search is triggered.
        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            isFollowingRequest = false
            if groups == nil { render(on: mapView) } // groups stay as they are once made
            revealSelection(on: mapView)
            // Measured to the top of the map rather than of the padded area, so opening the card is not a move.
            let top = mapView.projection.coordinate(for: CGPoint(x: mapView.bounds.midX, y: mapView.safeAreaInsets.top))
            let radius = CLLocation(latitude: position.target.latitude, longitude: position.target.longitude)
                .distance(from: CLLocation(latitude: top.latitude, longitude: position.target.longitude))
            // The whole map below the navigation bar, so a search covers everything on screen.
            let topLeft = mapView.projection.coordinate(for: CGPoint(x: 0, y: mapView.safeAreaInsets.top))
            let bottomRight = mapView.projection.coordinate(for: CGPoint(x: mapView.bounds.maxX, y: mapView.bounds.maxY))
            let bounds = GeoBounds(southWest: Coordinate(latitude: bottomRight.latitude, longitude: topLeft.longitude),
                                   northEast: Coordinate(latitude: topLeft.latitude, longitude: bottomRight.longitude))
            parent.onMove(Coordinate(position.target), radius, bounds)
        }
    }
}
