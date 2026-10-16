import GoogleMaps
import MapKit
import UIKit

/// The look of the Map tab: a quiet jet basemap that keeps land, water, parks, roads and place
/// names, and drops everything else (businesses, landmarks, transit, road shields, indoor maps),
/// so the only places on the map are the app's own pins.
///
/// Every colour is a palette colour, or one laid over jet at a given strength and flattened to
/// a single value, because map styles take opaque colours.
enum MapStyle {
    // MARK: Palette, as the map uses it

    static let water = hex(Theme.jetHex)
    static let land = mix(Theme.alabasterHex, 0.06, over: Theme.jetHex)
    static let buildings = mix(Theme.alabasterHex, 0.10, over: Theme.jetHex)
    static let parks = mix(Theme.seagrassHex, 0.22, over: Theme.jetHex)
    static let localRoads = mix(Theme.alabasterHex, 0.13, over: Theme.jetHex)
    static let arterialRoads = mix(Theme.alabasterHex, 0.20, over: Theme.jetHex)
    static let highways = mix(Theme.alabasterHex, 0.30, over: Theme.jetHex)
    static let borders = mix(Theme.alabasterHex, 0.22, over: Theme.jetHex)
    static let cityLabels = hex(Theme.alabasterHex)
    static let areaLabels = mix(Theme.alabasterHex, 0.62, over: Theme.jetHex)
    static let roadLabels = mix(Theme.alabasterHex, 0.48, over: Theme.jetHex)
    static let waterLabels = mix(Theme.seagrassHex, 0.80, over: Theme.jetHex)

    // MARK: Google (live)

    static let google: GMSMapStyle? = {
        let rules: [[String: Any]] = [
            // Base: everything is land-coloured and unlabelled until a rule below says otherwise.
            rule(element: "geometry", ["color": land]),
            rule(element: "labels.icon", ["visibility": "off"]),
            rule(element: "labels.text.fill", ["color": areaLabels]),
            rule(element: "labels.text.stroke", ["color": water]),

            // Points of interest and transit are hidden; park shapes stay as green space.
            rule("poi", ["visibility": "off"]),
            rule("poi.park", element: "geometry", ["visibility": "on"], ["color": parks]),
            rule("transit", ["visibility": "off"]),

            rule("water", element: "geometry", ["color": water]),
            rule("water", element: "labels.text.fill", ["color": waterLabels]),
            rule("landscape.man_made", element: "geometry", ["color": buildings]),

            // Roads brighten with importance; names are soft and never shielded.
            rule("road", element: "geometry.stroke", ["visibility": "off"]),
            rule("road.local", element: "geometry.fill", ["color": localRoads]),
            rule("road.arterial", element: "geometry.fill", ["color": arterialRoads]),
            rule("road.highway", element: "geometry.fill", ["color": highways]),
            rule("road", element: "labels.text.fill", ["color": roadLabels]),

            // Place names: cities strongest, then regions, then neighbourhoods.
            rule("administrative", element: "geometry.stroke", ["color": borders]),
            rule("administrative.land_parcel", ["visibility": "off"]),
            rule("administrative.locality", element: "labels.text.fill", ["color": cityLabels]),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return try? GMSMapStyle(jsonString: json)
    }()

    static func apply(to map: GMSMapView) {
        map.mapStyle = google
        map.backgroundColor = UIColor(hex: Theme.jetHex) // no grey flash before tiles load
        map.overrideUserInterfaceStyle = .dark // light Google logo on the dark map
        map.isIndoorEnabled = false
        map.settings.indoorPicker = false
    }

    // MARK: Apple (demo)

    /// MapKit can't be recoloured, so the demo uses Apple's muted dark map without points of
    /// interest, with a jet wash laid between the roads and the labels.
    static func apply(to map: MKMapView) {
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll // keep real businesses out of a fictional demo
        configuration.showsTraffic = false
        map.preferredConfiguration = configuration
        map.overrideUserInterfaceStyle = .dark
        map.addOverlay(Wash(), level: .aboveRoads)
    }

    /// A world-sized overlay; its renderer tints whatever lies beneath it.
    final class Wash: NSObject, MKOverlay {
        let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let boundingMapRect = MKMapRect.world

        static func renderer(for wash: Wash) -> MKOverlayRenderer {
            let renderer = Renderer(overlay: wash)
            renderer.alpha = 0.5
            return renderer
        }

        private final class Renderer: MKOverlayRenderer {
            override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
                context.setFillColor(UIColor(hex: Theme.jetHex).cgColor)
                context.fill(rect(for: mapRect))
            }
        }
    }

    // MARK: Pins

    /// A round badge in the pin's colour, ringed in alabaster, with the pin's symbol.
    static func badge(for pin: MapPin, selected: Bool) -> UIImage {
        let diameter: CGFloat = selected ? 44 : 32
        let margin: CGFloat = 4 // room for the shadow
        let size = CGSize(width: diameter + margin * 2, height: diameter + margin * 2)
        return UIGraphicsImageRenderer(size: size).image { context in
            let circle = CGRect(x: margin, y: margin, width: diameter, height: diameter)
            let alabaster = UIColor(hex: Theme.alabasterHex)

            context.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                                        color: UIColor.black.withAlphaComponent(0.4).cgColor)
            alabaster.setFill()
            UIBezierPath(ovalIn: circle).fill()
            context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

            pin.color.setFill()
            UIBezierPath(ovalIn: circle.insetBy(dx: 2, dy: 2)).fill()

            let weight = UIImage.SymbolConfiguration(pointSize: diameter * 0.38, weight: .bold)
            if let symbol = UIImage(systemName: pin.symbol, withConfiguration: weight)?
                .withTintColor(alabaster, renderingMode: .alwaysOriginal) {
                symbol.draw(at: CGPoint(x: circle.midX - symbol.size.width / 2, y: circle.midY - symbol.size.height / 2))
            }
        }
    }

    // MARK: Helpers

    private static func rule(_ feature: String? = nil, element: String? = nil, _ stylers: [String: String]...) -> [String: Any] {
        var rule: [String: Any] = ["stylers": stylers]
        rule["featureType"] = feature
        rule["elementType"] = element
        return rule
    }

    private static func hex(_ value: UInt32) -> String {
        String(format: "#%06X", value)
    }

    /// `color` at `opacity` over `base`, as one opaque colour.
    private static func mix(_ color: UInt32, _ opacity: Double, over base: UInt32) -> String {
        func channel(_ shift: UInt32) -> UInt32 {
            let top = Double((color >> shift) & 0xFF), bottom = Double((base >> shift) & 0xFF)
            return UInt32((bottom + (top - bottom) * opacity).rounded())
        }
        return hex(channel(16) << 16 | channel(8) << 8 | channel(0))
    }
}
