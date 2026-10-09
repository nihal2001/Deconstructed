import CoreLocation
import Foundation
import GoogleMaps
import GooglePlaces

/// Google Places (New) behind the `PlacesProvider` interface.
///
/// Field masks decide the billing SKU, so each call asks for the least it needs:
///   - location  → Place Details Essentials (coordinate only, for saved pins)
///   - core      → Place Details Pro / Text Search Pro / Nearby Search Pro
///   - extended  → Place Details Enterprise, only when the user asks for more
/// Photos, ratings and reviews are never requested. See docs/google-api-usage.md.
@MainActor
final class GooglePlacesProvider: PlacesProvider {
    let providerKey = "google"
    let isDemo = false

    private static let coreFields: [GMSPlaceProperty] = [.placeID, .name, .coordinate, .formattedAddress, .types, .addressComponents]
    private static let extendedFields: [GMSPlaceProperty] = coreFields + [.priceLevel, .website, .phoneNumber, .currentOpeningHours]
    private static let foodTypes = ["restaurant", "cafe", "bakery", "bar", "meal_takeaway"]

    private var client: GMSPlacesClient { .shared() }

    init(apiKey: String) {
        GMSServices.provideAPIKey(apiKey)
        GMSPlacesClient.provideAPIKey(apiKey)
    }

    func autocomplete(query: String, near: Coordinate?, session: PlacesSession) async throws -> [PlaceSuggestion] {
        let filter = GMSAutocompleteFilter()
        filter.types = Self.foodTypes
        if let near {
            filter.locationBias = GMSPlaceCircularLocationOption(near.clLocation, 20_000)
            filter.origin = CLLocation(latitude: near.latitude, longitude: near.longitude)
        }
        let request = GMSAutocompleteRequest(query: query)
        request.filter = filter
        request.sessionToken = token(for: session)

        let suggestions: [GMSAutocompleteSuggestion] = try await withCheckedThrowingContinuation { continuation in
            client.fetchAutocompleteSuggestions(from: request) { results, error in
                if let error {
                    continuation.resume(throwing: Self.map(error))
                } else {
                    continuation.resume(returning: results ?? [])
                }
            }
        }
        return suggestions.compactMap(\.placeSuggestion).map {
            PlaceSuggestion(placeID: $0.placeID, title: $0.attributedPrimaryText.string,
                            subtitle: $0.attributedSecondaryText?.string)
        }
    }

    func searchText(_ query: String, near: Coordinate?) async throws -> [Place] {
        let request = GMSPlaceSearchByTextRequest(textQuery: query, placeProperties: Self.coreFields.map(\.rawValue))
        request.includedType = "restaurant"
        request.maxResultCount = 15
        if let near {
            request.locationBias = GMSPlaceCircularLocationOption(near.clLocation, 10_000)
        }
        let places: [GMSPlace] = try await withCheckedThrowingContinuation { continuation in
            client.searchByText(with: request) { (response: GMSPlaceSearchByTextResponse?, error: Error?) in
                if let error {
                    continuation.resume(throwing: Self.map(error))
                } else {
                    continuation.resume(returning: response?.places ?? [])
                }
            }
        }
        return places.compactMap { Self.place(from: $0, level: .core) }
    }

    func searchNearby(center: Coordinate, radiusMeters: Double) async throws -> [Place] {
        let request = GMSPlaceSearchNearbyRequest(
            locationRestriction: GMSPlaceCircularLocationOption(center.clLocation, radiusMeters),
            placeProperties: Self.coreFields.map(\.rawValue))
        request.includedTypes = Self.foodTypes
        request.maxResultCount = 20
        let places: [GMSPlace] = try await withCheckedThrowingContinuation { continuation in
            client.searchNearby(with: request) { (response: GMSPlaceSearchNearbyResponse?, error: Error?) in
                if let error {
                    continuation.resume(throwing: Self.map(error))
                } else {
                    continuation.resume(returning: response?.places ?? [])
                }
            }
        }
        return places.compactMap { Self.place(from: $0, level: .core) }
    }

    func details(placeID: String, level: PlaceDetailLevel, session: PlacesSession?) async throws -> Place {
        let fields: [GMSPlaceProperty] = switch level {
        case .location: [.placeID, .coordinate]
        case .core: Self.coreFields
        case .extended: Self.extendedFields
        }
        // Passing the session token here is what ends the autocomplete session.
        let request = GMSFetchPlaceRequest(placeID: placeID, placeProperties: fields.map(\.rawValue),
                                           sessionToken: session.map(token(for:)))
        let result: GMSPlace? = try await withCheckedThrowingContinuation { continuation in
            client.fetchPlace(with: request) { place, error in
                if let error {
                    continuation.resume(throwing: Self.map(error, isLookup: true))
                } else {
                    continuation.resume(returning: place)
                }
            }
        }
        guard let result, var place = Self.place(from: result, level: level) else { throw PlacesError.notFound }
        place.placeID = placeID
        return place
    }

    // MARK: Mapping

    private func token(for session: PlacesSession) -> GMSAutocompleteSessionToken {
        if let existing = session.providerToken as? GMSAutocompleteSessionToken { return existing }
        let token = GMSAutocompleteSessionToken()
        session.providerToken = token
        return token
    }

    private nonisolated static func place(from source: GMSPlace, level: PlaceDetailLevel) -> Place? {
        guard let placeID = source.placeID else { return nil }
        let coordinate = CLLocationCoordinate2DIsValid(source.coordinate)
            && !(source.coordinate.latitude == 0 && source.coordinate.longitude == 0)
            ? Coordinate(source.coordinate) : nil
        var place = Place(placeID: placeID, level: level, coordinate: coordinate)
        guard level >= .core else { return place }

        place.name = source.name
        place.address = source.formattedAddress
        place.cuisine = cuisine(from: source.types ?? [])
        place.area = area(from: source.addressComponents ?? [])
        place.thirdPartyAttribution = source.attributions?.string

        if level >= .extended {
            let price = source.priceLevel.rawValue
            place.priceLevel = price > 0 ? price : nil
            place.website = source.website
            place.phone = source.phoneNumber
            place.openingHours = source.currentOpeningHours?.weekdayText ?? []
        }
        return place
    }

    /// "italian_restaurant" → "Italian"; falls back to broader categories.
    private nonisolated static func cuisine(from types: [String]) -> String? {
        if let specific = types.first(where: { $0.hasSuffix("_restaurant") }) {
            return specific.dropLast("_restaurant".count).replacingOccurrences(of: "_", with: " ").capitalized
        }
        let fallbacks = ["cafe": "Café", "bakery": "Bakery", "bar": "Bar", "meal_takeaway": "Takeaway",
                         "coffee_shop": "Coffee", "ice_cream_shop": "Ice cream", "food_court": "Food court"]
        return types.lazy.compactMap { fallbacks[$0] }.first
    }

    private nonisolated static func area(from components: [GMSAddressComponent]) -> String? {
        for wanted in ["neighborhood", "sublocality_level_1", "sublocality", "locality", "postal_town"] {
            if let match = components.first(where: { $0.types.contains(wanted) }) { return match.name }
        }
        return nil
    }

    private nonisolated static func map(_ error: Error, isLookup: Bool = false) -> PlacesError {
        let nsError = error as NSError
        guard nsError.domain == kGMSPlacesErrorDomain, let code = GMSPlacesErrorCode(rawValue: nsError.code) else {
            return nsError.domain == NSURLErrorDomain ? .network : .other(error.localizedDescription)
        }
        switch code {
        case .networkError:
            return .network
        case .usageLimitExceeded, .rateLimitExceeded, .deviceRateLimitExceeded:
            return .quotaExhausted
        case .keyInvalid, .keyExpired, .accessNotConfigured, .incorrectBundleIdentifier:
            return .notConfigured("the Google API key was rejected (\(nsError.localizedDescription)). Check the key, its iOS app restriction and that Places API (New) is enabled.")
        case .invalidRequest:
            return isLookup ? .notFound : .other(error.localizedDescription)
        default:
            return .other(error.localizedDescription)
        }
    }
}
