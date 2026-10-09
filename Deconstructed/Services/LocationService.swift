import CoreLocation
import Foundation
import Observation

struct NamedArea: Codable, Hashable {
    var name: String
    var coordinate: Coordinate
}

/// Device location plus a manual fallback, so every location-dependent feature still works
/// when permission is denied.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum Access {
        case notDetermined, denied, granted
    }

    private(set) var access: Access = .notDetermined
    private(set) var current: Coordinate?
    /// An area the user picked by hand. Takes priority over the device location while set.
    var manualArea: NamedArea? {
        didSet { saveManualArea() }
    }

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let manualKey = "manual-area"

    /// Where searches should be centred, or nil if the user has given us nothing to go on.
    var searchOrigin: Coordinate? { manualArea?.coordinate ?? current }

    var originLabel: String {
        if let manualArea { return manualArea.name }
        switch access {
        case .granted: return current == nil ? "Finding your location…" : "Current location"
        case .denied: return "Location off"
        case .notDetermined: return "No area set"
        }
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if let data = defaults.data(forKey: Self.manualKey) {
            manualArea = try? JSONDecoder().decode(NamedArea.self, from: data)
        }
        update(status: manager.authorizationStatus)
    }

    func requestAccess() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: break
        }
    }

    func useDeviceLocation() {
        manualArea = nil
        requestAccess()
    }

    /// Turns a typed neighbourhood, city or postcode into an area using Apple's geocoder.
    func setManualArea(matching text: String) async throws {
        let query = text.trimmed
        guard !query.isEmpty else { return }
        let placemarks = try await CLGeocoder().geocodeAddressString(query)
        guard let placemark = placemarks.first, let location = placemark.location else {
            throw CLError(.geocodeFoundNoResult)
        }
        let name = [placemark.subLocality ?? placemark.locality ?? placemark.name, placemark.administrativeArea]
            .compactMap { $0 }.joined(separator: ", ")
        manualArea = NamedArea(name: name.isEmpty ? query : name, coordinate: Coordinate(location.coordinate))
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.update(status: status)
            if self.access == .granted { manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in self.current = Coordinate(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A failed fix is not fatal: the manual area flow covers it.
    }

    private func update(status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: access = .granted
        case .denied, .restricted: access = .denied
        default: access = .notDetermined
        }
    }

    private func saveManualArea() {
        if let manualArea, let data = try? JSONEncoder().encode(manualArea) {
            defaults.set(data, forKey: Self.manualKey)
        } else {
            defaults.removeObject(forKey: Self.manualKey)
        }
    }
}
