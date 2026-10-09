import Foundation

/// Build-time configuration, read from Info.plist values that xcconfig files fill in.
/// Nothing secret is compiled into source; see Config/Secrets.example.xcconfig.
struct AppConfig {
    var googleMapsAPIKey: String?
    var supabaseURL: URL?
    var supabaseAnonKey: String?
    var placesLimits = RequestMonitor.Limits(perMinute: 30, perDay: 400)
    var autocompleteMinCharacters = 3
    var autocompleteDebounce: Duration = .milliseconds(350)

    /// Live services are used only when every credential is present. A partial setup falls
    /// back to the demo rather than mixing real search results with fictional accounts.
    var isLive: Bool { missingCredentials.isEmpty }

    var missingCredentials: [String] {
        var missing: [String] = []
        if googleMapsAPIKey == nil { missing.append("GOOGLE_MAPS_API_KEY") }
        if supabaseURL == nil { missing.append("SUPABASE_PROJECT_HOST") }
        if supabaseAnonKey == nil { missing.append("SUPABASE_ANON_KEY") }
        return missing
    }

    static let current = AppConfig(bundle: .main)

    init() {}

    init(bundle: Bundle) {
        func string(_ key: String) -> String? {
            guard let value = (bundle.object(forInfoDictionaryKey: key) as? String)?.trimmed,
                  !value.isEmpty, !value.hasPrefix("$(") else { return nil }
            return value
        }
        googleMapsAPIKey = string("GoogleMapsAPIKey")
        supabaseAnonKey = string("SupabaseAnonKey")
        if let host = string("SupabaseProjectHost") {
            let bare = host.replacingOccurrences(of: "https://", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            supabaseURL = URL(string: "https://\(bare)")
        }
        if let perMinute = string("PlacesMaxRequestsPerMinute").flatMap(Int.init), perMinute > 0 {
            placesLimits.perMinute = perMinute
        }
        if let perDay = string("PlacesMaxRequestsPerDay").flatMap(Int.init), perDay > 0 {
            placesLimits.perDay = perDay
        }
        if let minimum = string("PlacesAutocompleteMinCharacters").flatMap(Int.init), minimum > 0 {
            autocompleteMinCharacters = minimum
        }
        if let debounce = string("PlacesAutocompleteDebounceMs").flatMap(Int.init), debounce >= 0 {
            autocompleteDebounce = .milliseconds(debounce)
        }
    }
}

/// The set of services the app runs against. Screens only ever see the protocols.
@MainActor
struct AppEnvironment {
    let config: AppConfig
    let backend: BackendService
    let places: PlacesProvider
    let monitor: RequestMonitor
    let demoControls: DemoControls
    /// Present only in the demo, for the "reset demo data" action.
    let demoBackend: DemoBackend?

    var isDemo: Bool { backend.isDemo }

    static func make(config: AppConfig = .current) -> AppEnvironment {
        let controls = DemoControls()
        let monitor = RequestMonitor(limits: config.placesLimits)
        if config.isLive, let key = config.googleMapsAPIKey, let url = config.supabaseURL, let anon = config.supabaseAnonKey {
            return AppEnvironment(
                config: config,
                backend: SupabaseBackend(url: url, anonKey: anon),
                places: MeteredPlacesProvider(base: GooglePlacesProvider(apiKey: key), monitor: monitor),
                monitor: monitor, demoControls: controls, demoBackend: nil)
        }
        let backend = DemoBackend(persist: true, controls: controls)
        return AppEnvironment(
            config: config, backend: backend,
            places: MeteredPlacesProvider(base: DemoPlacesProvider(controls: controls), monitor: monitor),
            monitor: monitor, demoControls: controls, demoBackend: backend)
    }

    /// An isolated, non-persistent demo environment for previews and tests.
    static func ephemeralDemo(places: PlacesProvider? = nil, seed: DemoState? = nil) -> AppEnvironment {
        let controls = DemoControls()
        let monitor = RequestMonitor(limits: .init(perMinute: 10_000, perDay: 100_000), defaults: nil)
        let backend = DemoBackend(persist: false, controls: controls, seed: seed)
        return AppEnvironment(
            config: AppConfig(), backend: backend,
            places: places ?? MeteredPlacesProvider(base: DemoPlacesProvider(controls: controls, latency: .zero), monitor: monitor),
            monitor: monitor, demoControls: controls, demoBackend: backend)
    }
}
