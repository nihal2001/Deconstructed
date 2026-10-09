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
        case .wantToTry: UIColor(hex: 0x91972A)
        case .visited: UIColor(hex: 0x519E8A)
        case .result: UIColor(hex: 0xD65780)
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
    var bottomInset: CGFloat
    var onMove: (Coordinate, Double) -> Void

    var body: some View {
        if usesGoogle {
            GoogleMapView(pins: pins, selection: $selection, camera: camera, showsUserLocation: showsUserLocation,
                          bottomInset: bottomInset, onMove: onMove)
        } else {
            AppleMapView(pins: pins, selection: $selection, camera: camera, showsUserLocation: showsUserLocation,
                         onMove: onMove)
        }
    }
}

// MARK: - Apple (demo)

struct AppleMapView: UIViewRepresentable {
    var pins: [MapPin]
    @Binding var selection: String?
    var camera: MapCameraRequest?
    var showsUserLocation: Bool
    var onMove: (Coordinate, Double) -> Void

    final class PinAnnotation: NSObject, MKAnnotation {
        let pin: MapPin
        var coordinate: CLLocationCoordinate2D { pin.coordinate.clLocation }
        init(pin: MapPin) { self.pin = pin }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll // keep real businesses out of a fictional demo
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

        init(_ parent: AppleMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: annotation) as? MKMarkerAnnotationView
                view?.markerTintColor = UIColor(hex: 0x143642)
                view?.glyphText = "\(cluster.memberAnnotations.count)"
                view?.accessibilityLabel = "\(cluster.memberAnnotations.count) restaurants. Double tap to zoom in."
                return view
            }
            guard let annotation = annotation as? PinAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "pin", for: annotation) as? MKMarkerAnnotationView
            view?.clusteringIdentifier = "restaurant"
            view?.markerTintColor = annotation.pin.color
            view?.glyphImage = UIImage(systemName: annotation.pin.symbol)
            view?.displayPriority = annotation.pin.kind == .result ? .defaultHigh : .required
            view?.accessibilityLabel = switch annotation.pin.kind {
            case .wantToTry: "Want to try"
            case .visited: "Visited"
            case .result: "Search result"
            }
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let cluster = annotation as? MKClusterAnnotation {
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
                mapView.deselectAnnotation(annotation, animated: false)
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
            parent.onMove(Coordinate(region.center), radius)
        }
    }
}

// MARK: - Google (live)

struct GoogleMapView: UIViewRepresentable {
    var pins: [MapPin]
    @Binding var selection: String?
    var camera: MapCameraRequest?
    var showsUserLocation: Bool
    var bottomInset: CGFloat
    var onMove: (Coordinate, Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GMSMapView {
        let map = GMSMapView(options: GMSMapViewOptions())
        map.delegate = context.coordinator
        map.settings.rotateGestures = false
        map.settings.tiltGestures = false
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        map.isMyLocationEnabled = showsUserLocation
        // Keeps the Google logo and attribution clear of the app's own overlays.
        map.padding = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)

        if let camera, camera.id != coordinator.lastCameraID {
            coordinator.lastCameraID = camera.id
            let latDelta = camera.radiusMeters / 111_000
            let lngDelta = latDelta / max(0.2, cos(camera.center.latitude * .pi / 180))
            let bounds = GMSCoordinateBounds(
                coordinate: CLLocationCoordinate2D(latitude: camera.center.latitude + latDelta, longitude: camera.center.longitude + lngDelta),
                coordinate: CLLocationCoordinate2D(latitude: camera.center.latitude - latDelta, longitude: camera.center.longitude - lngDelta))
            let update = GMSCameraUpdate.fit(bounds, withPadding: 24)
            if coordinator.hasSetCamera { map.animate(with: update) } else { map.moveCamera(update) }
            coordinator.hasSetCamera = true
        }

        if coordinator.pins != pins || coordinator.renderedSelection != selection {
            coordinator.pins = pins
            coordinator.render(on: map)
        }
    }

    /// Draws markers and groups those that would overlap on screen into count markers.
    /// Clustering is recomputed locally whenever the camera settles; it makes no requests.
    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleMapView
        var pins: [MapPin] = []
        var lastCameraID: UUID?
        var hasSetCamera = false
        var renderedSelection: String?
        private var markers: [GMSMarker] = []
        private let cellSize: CGFloat = 56

        init(_ parent: GoogleMapView) { self.parent = parent }

        func render(on map: GMSMapView) {
            markers.forEach { $0.map = nil }
            markers = []
            renderedSelection = parent.selection

            var cells: [String: [MapPin]] = [:]
            for pin in pins {
                let point = map.projection.point(for: pin.coordinate.clLocation)
                // The selected pin always stands alone so it stays tappable and visible.
                let key = pin.id == parent.selection
                    ? "selected"
                    : "\(Int((point.x / cellSize).rounded(.down))):\(Int((point.y / cellSize).rounded(.down)))"
                cells[key, default: []].append(pin)
            }

            for group in cells.values {
                let marker: GMSMarker
                if group.count == 1, let pin = group.first {
                    marker = GMSMarker(position: pin.coordinate.clLocation)
                    marker.icon = GMSMarker.markerImage(with: pin.color)
                    marker.userData = [pin.id]
                    marker.zIndex = pin.id == parent.selection ? 10 : 1
                    marker.accessibilityLabel = switch pin.kind {
                    case .wantToTry: "Want to try"
                    case .visited: "Visited"
                    case .result: "Search result"
                    }
                } else {
                    let lat = group.map(\.coordinate.latitude).reduce(0, +) / Double(group.count)
                    let lng = group.map(\.coordinate.longitude).reduce(0, +) / Double(group.count)
                    marker = GMSMarker(position: CLLocationCoordinate2D(latitude: lat, longitude: lng))
                    marker.iconView = Self.clusterView(count: group.count)
                    marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                    marker.userData = group.map(\.id)
                    marker.accessibilityLabel = "\(group.count) restaurants. Double tap to zoom in."
                }
                marker.map = map
                markers.append(marker)
            }
        }

        private static func clusterView(count: Int) -> UIView {
            let label = UILabel(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
            label.text = "\(count)"
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 15, weight: .bold)
            label.textColor = .white
            label.backgroundColor = UIColor(hex: 0x143642)
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
                var bounds = GMSCoordinateBounds()
                for pin in pins where ids.contains(pin.id) { bounds = bounds.includingCoordinate(pin.coordinate.clLocation) }
                mapView.animate(with: GMSCameraUpdate.fit(bounds, withPadding: 80))
            }
            return true
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            parent.selection = nil
        }

        // Camera settled: regroup markers and report the new area. No search is triggered.
        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            render(on: mapView)
            let region = mapView.projection.visibleRegion()
            let radius = CLLocation(latitude: position.target.latitude, longitude: position.target.longitude)
                .distance(from: CLLocation(latitude: region.farLeft.latitude, longitude: position.target.longitude))
            parent.onMove(Coordinate(position.target), radius)
        }
    }
}
