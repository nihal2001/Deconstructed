import Foundation
import Observation

/// Switches for rehearsing failure states in the demo. They have no effect on live services.
@MainActor
@Observable
final class DemoControls {
    var simulateQuotaExhausted = false
    var simulateOffline = false
}

/// Which starter rubric suits a demo restaurant's format. Used only to seed believable data.
enum DemoFormat {
    case general, fineDining, fastCasual, noodles

    var systemID: UUID {
        switch self {
        case .general, .noodles: StarterSystems.general
        case .fineDining: StarterSystems.fineDining
        case .fastCasual: StarterSystems.fastCasual
        }
    }
}

struct DemoRestaurant {
    var placeID: String
    var name: String
    var cuisine: String
    var area: String
    var street: String
    var coordinate: Coordinate
    var priceLevel: Int
    var format: DemoFormat
    /// 0...1, steers seeded scores so the demo has clear favourites and duds.
    var quality: Double

    var place: Place {
        Place(placeID: placeID, level: .extended, name: name,
              address: "\(street), \(area) (fictional address)",
              coordinate: coordinate, cuisine: cuisine, area: area, priceLevel: priceLevel,
              website: nil, phone: nil,
              openingHours: ["Demo listing. Opening hours are not real."],
              thirdPartyAttribution: nil, isDemo: true)
    }
}

/// Every restaurant here is invented. Pins sit in real San Francisco neighbourhoods only so
/// the map has something sensible to show; none of them corresponds to a real business.
enum DemoCatalog {
    static let providerKey = "demo"
    static let home = Coordinate(latitude: 37.7763, longitude: -122.4242)

    static let areas: [(name: String, coordinate: Coordinate)] = [
        ("Hayes Valley", Coordinate(latitude: 37.7763, longitude: -122.4242)),
        ("Mission", Coordinate(latitude: 37.7599, longitude: -122.4148)),
        ("North Beach", Coordinate(latitude: 37.8005, longitude: -122.4103)),
        ("Inner Richmond", Coordinate(latitude: 37.7799, longitude: -122.4647)),
        ("Sunset", Coordinate(latitude: 37.7533, longitude: -122.4860)),
    ]

    static let restaurants: [DemoRestaurant] = [
        r("saltmarsh", "Saltmarsh & Rye", "New American", "Hayes Valley", "14 Sample Street", 37.7768, -122.4236, 3, .general, 0.82),
        r("casa-limonada", "Casa Limonada", "Mexican", "Mission", "220 Placeholder Avenue", 37.7604, -122.4159, 2, .general, 0.74),
        r("nine-lanterns", "Nine Lanterns Noodle Bar", "Ramen", "Japantown", "8 Example Lane", 37.7851, -122.4301, 2, .noodles, 0.88),
        r("gilded-radish", "The Gilded Radish", "Tasting menu", "Nob Hill", "1 Fictional Terrace", 37.7928, -122.4157, 4, .fineDining, 0.93),
        r("paper-crane", "Paper Crane Sushi", "Sushi", "Inner Richmond", "301 Demo Boulevard", 37.7803, -122.4639, 3, .general, 0.79),
        r("bodega-sol", "Bodega Sol Tacos", "Tacos", "Mission", "77 Sample Street", 37.7589, -122.4133, 1, .fastCasual, 0.91),
        r("little-furnace", "Little Furnace Pizza", "Pizza", "North Beach", "45 Placeholder Avenue", 37.8001, -122.4097, 2, .fastCasual, 0.77),
        r("marens-table", "Maren's Table", "Californian", "SoMa", "500 Example Lane", 37.7790, -122.4052, 4, .fineDining, 0.71),
        r("dumpling-almanac", "Dumpling Almanac", "Chinese", "Inner Richmond", "112 Demo Boulevard", 37.7794, -122.4662, 1, .fastCasual, 0.85),
        r("fig-ember", "Fig & Ember", "Mediterranean", "Marina", "9 Fictional Terrace", 37.8006, -122.4371, 3, .general, 0.66),
        r("brassica", "Brassica Counter", "Vegetarian", "SoMa", "63 Sample Street", 37.7779, -122.4071, 2, .fastCasual, 0.58),
        r("harbor-light", "Harbor Light Oyster Room", "Seafood", "Embarcadero", "2 Placeholder Pier", 37.7957, -122.3941, 3, .general, 0.84),
        r("tandoor-lane", "Tandoor Lane", "Indian", "Tenderloin", "190 Example Lane", 37.7845, -122.4147, 2, .general, 0.80),
        r("ostra-azul", "Ostra Azul", "Peruvian", "Mission", "340 Demo Boulevard", 37.7622, -122.4121, 3, .general, 0.87),
        r("copper-kettle", "Copper Kettle Diner", "Diner", "Sunset", "21 Fictional Terrace", 37.7538, -122.4853, 1, .general, 0.49),
        r("pho-lantern", "Pho Lantern", "Vietnamese", "Sunset", "88 Sample Street", 37.7527, -122.4871, 1, .noodles, 0.81),
        r("olive-thistle", "Olive & Thistle", "Italian", "North Beach", "130 Placeholder Avenue", 37.8011, -122.4112, 3, .general, 0.76),
        r("kiln-bakery", "Kiln Bakery Café", "Bakery", "Hayes Valley", "52 Example Lane", 37.7757, -122.4251, 1, .fastCasual, 0.90),
        r("smokestack", "Smokestack Sandwich Co.", "Sandwiches", "Dogpatch", "6 Demo Boulevard", 37.7611, -122.3890, 2, .fastCasual, 0.69),
        r("miso-hour", "Miso Hour", "Izakaya", "Japantown", "17 Fictional Terrace", 37.7858, -122.4290, 2, .general, 0.73),
    ]

    static func restaurant(placeID: String) -> DemoRestaurant? {
        restaurants.first { $0.placeID == placeID }
    }

    private static func r(_ slug: String, _ name: String, _ cuisine: String, _ area: String, _ street: String,
                          _ lat: Double, _ lng: Double, _ price: Int, _ format: DemoFormat, _ quality: Double) -> DemoRestaurant {
        DemoRestaurant(placeID: "demo-\(slug)", name: name, cuisine: cuisine, area: area, street: street,
                       coordinate: Coordinate(latitude: lat, longitude: lng), priceLevel: price,
                       format: format, quality: quality)
    }
}

/// Stands in for Google Places with fictional data. Every result carries `isDemo = true`
/// so screens can label it and never pass it off as a real search result.
@MainActor
final class DemoPlacesProvider: PlacesProvider {
    let providerKey = DemoCatalog.providerKey
    let isDemo = true
    private let controls: DemoControls
    private let latency: Duration

    init(controls: DemoControls, latency: Duration = .milliseconds(280)) {
        self.controls = controls
        self.latency = latency
    }

    func autocomplete(query: String, near: Coordinate?, session: PlacesSession) async throws -> [PlaceSuggestion] {
        try await simulate()
        return matches(query).prefix(5).map {
            PlaceSuggestion(placeID: $0.placeID, title: $0.name, subtitle: "\($0.cuisine) · \($0.area)", isDemo: true)
        }
    }

    func searchText(_ query: String, near: Coordinate?) async throws -> [Place] {
        try await simulate()
        return sorted(matches(query), near: near).map { core($0) }
    }

    func searchNearby(center: Coordinate, radiusMeters: Double) async throws -> [Place] {
        try await simulate()
        let nearby = DemoCatalog.restaurants.filter { $0.coordinate.distance(to: center) <= radiusMeters }
        return sorted(nearby, near: center).prefix(20).map { core($0) }
    }

    func details(placeID: String, level: PlaceDetailLevel, session: PlacesSession?) async throws -> Place {
        try await simulate()
        guard let restaurant = DemoCatalog.restaurant(placeID: placeID) else { throw PlacesError.notFound }
        switch level {
        case .location:
            return Place(placeID: placeID, level: .location, coordinate: restaurant.coordinate, isDemo: true)
        case .core:
            return core(restaurant)
        case .extended:
            return restaurant.place
        }
    }

    private func core(_ restaurant: DemoRestaurant) -> Place {
        var place = restaurant.place
        place.level = .core
        place.priceLevel = nil
        place.openingHours = []
        return place
    }

    private func matches(_ query: String) -> [DemoRestaurant] {
        let needle = query.trimmed.lowercased()
        guard !needle.isEmpty else { return [] }
        return DemoCatalog.restaurants.filter {
            [$0.name, $0.cuisine, $0.area].contains { $0.lowercased().contains(needle) }
        }
    }

    private func sorted(_ restaurants: [DemoRestaurant], near: Coordinate?) -> [DemoRestaurant] {
        guard let near else { return restaurants }
        return restaurants.sorted { $0.coordinate.distance(to: near) < $1.coordinate.distance(to: near) }
    }

    private func simulate() async throws {
        try await Task.sleep(for: latency)
        if controls.simulateOffline { throw PlacesError.network }
        if controls.simulateQuotaExhausted { throw PlacesError.quotaExhausted }
    }
}
