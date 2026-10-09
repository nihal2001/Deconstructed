import Charts
import GoogleMaps
import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var showEdit = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var distributionSystemID: UUID?

    private enum Destination: Hashable {
        case visited, saved, usage, legal
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let profile = model.profile { header(profile) }
                    stats
                    distribution
                    lists
                    privacy
                    settings
                    if model.isDemo { demoTools }
                    account
                }
                .padding(Theme.spacing)
            }
            .screenBackground()
            .navigationTitle("Profile")
            .appRoutes()
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .visited: VisitedListView()
                case .saved: SavedListView()
                case .usage: UsageView()
                case .legal: LegalView()
                }
            }
            .sheet(isPresented: $showEdit) { EditProfileSheet() }
        }
    }

    // MARK: Sections

    private func header(_ profile: UserProfile) -> some View {
        HStack(spacing: 14) {
            Avatar(profile: profile, size: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName).font(.display(.title2, weight: .bold)).foregroundStyle(Theme.ink)
                Text("@\(profile.username)").font(.subheadline).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Button("Edit") { showEdit = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.alabaster)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.white.opacity(0.18), in: Capsule())
        }
        .hero()
    }

    private var stats: some View {
        HStack(spacing: 10) {
            StatTile(value: model.visitedRestaurantIDs.count, label: "Visited", symbol: "checkmark.circle.fill", fill: Theme.seagrassGradient)
            StatTile(value: model.saved.count, label: "Want to try", symbol: "bookmark.fill", fill: Theme.oliveGradient)
            StatTile(value: model.visits.filter(\.isCompleted).count, label: "Ratings", symbol: "star.fill", fill: Theme.roseGradient)
        }
    }

    @ViewBuilder
    private var distribution: some View {
        let options = model.mySystems.filter { model.hasRatings($0) }
        let system = options.first { $0.id == distributionSystemID }
            ?? options.first { $0.id == model.defaultSystem?.id } ?? options.first
        let scope: SystemScope? = system.flatMap { system in
            system.currentVersionID.map { .version(systemID: system.id, versionID: $0) }
        }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Score distribution")
                if options.count > 1 {
                    Picker("System", selection: Binding(get: { system?.id }, set: { distributionSystemID = $0 })) {
                        ForEach(options) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
            if let system, let scope {
                let buckets = RankingEngine.distribution(of: model.ranked(scope: scope))
                Chart(Array(buckets.enumerated()), id: \.offset) { total, count in
                    BarMark(x: .value("Total", "\(total)"), y: .value("Restaurants", count))
                        .foregroundStyle(total >= 9 ? Theme.roseGradient : total >= 7 ? Theme.seagrassGradient
                                         : total >= 4 ? Theme.oliveGradient : Theme.heroGradient)
                        .cornerRadius(5)
                        .accessibilityLabel("\(total) out of 10")
                        .accessibilityValue("\(count) restaurant\(count == 1 ? "" : "s")")
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { AxisGridLine(); AxisValueLabel() }
                }
                .frame(height: 140)
                Text("Latest \(system.name) score for each restaurant, current version. Other systems are counted separately.")
                    .font(.caption).foregroundStyle(Theme.inkSoft)
            } else {
                Text("Rate a few places and the spread of your scores appears here.")
                    .font(.subheadline).foregroundStyle(Theme.inkSoft)
            }
        }
        .card()
    }

    private var lists: some View {
        VStack(spacing: 0) {
            NavigationLink(value: Destination.visited) {
                SettingsRow(symbol: "checkmark.circle", title: "Visited restaurants", detail: "\(model.visitedRestaurantIDs.count)")
            }
            Divider()
            NavigationLink(value: Destination.saved) {
                SettingsRow(symbol: "bookmark", title: "Saved · want to try", detail: "\(model.saved.count)")
            }
        }
        .buttonStyle(.plain)
        .card(padding: 4)
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Privacy", detail: "The starting visibility for new reviews. You can change it on each visit.")
            Picker("Default review visibility", selection: Binding(
                get: { model.profile?.defaultVisibility ?? .followers },
                set: { newValue in
                    Task {
                        do { try await model.updateProfile { $0.defaultVisibility = newValue } }
                        catch { model.toast = error.localizedDescription }
                    }
                })) {
                ForEach(Visibility.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            ForEach(Visibility.allCases) { option in
                Label {
                    Text("\(Text(option.title).fontWeight(.semibold)): \(option.detail)")
                } icon: {
                    Image(systemName: option.symbol)
                }
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
            }
            Text("Anyone can follow you, and followers can read your followers-only reviews. Remove a follower from the Friends tab at any time.")
                .font(.caption).foregroundStyle(Theme.inkSoft)
        }
        .card()
    }

    private var settings: some View {
        VStack(spacing: 0) {
            NavigationLink(value: Route.rankingSystems) {
                SettingsRow(symbol: "slider.horizontal.3", title: "Ranking Systems", detail: model.defaultSystem?.name ?? "")
            }
            Divider()
            NavigationLink(value: Destination.usage) {
                SettingsRow(symbol: "gauge.with.dots.needle.33percent", title: "Search usage", detail: "\(model.environment.monitor.todayTotal) today")
            }
            Divider()
            NavigationLink(value: Destination.legal) {
                SettingsRow(symbol: "doc.text", title: "About and attributions", detail: "")
            }
        }
        .buttonStyle(.plain)
        .card(padding: 4)
    }

    private var demoTools: some View {
        @Bindable var controls = model.environment.demoControls
        return VStack(alignment: .leading, spacing: 12) {
            HStack { SectionTitle("Demo tools"); DemoBadge() }
            Toggle("Simulate search quota exhausted", isOn: $controls.simulateQuotaExhausted)
            Toggle("Simulate no network", isOn: $controls.simulateOffline)
            Text("Use these to see how search, saving and logging behave when things fail.")
                .font(.caption).foregroundStyle(Theme.inkSoft)
            AsyncButton("Reset demo data") { await model.resetDemo() }
                .buttonStyle(.secondary)
        }
        .font(.subheadline)
        .tint(Theme.rose)
        .card()
    }

    private var account: some View {
        VStack(spacing: 10) {
            Button("Sign out") { confirmSignOut = true }
                .buttonStyle(.secondary)
            Button("Delete account", role: .destructive) { confirmDelete = true }
                .buttonStyle(.secondary(tint: Theme.rose))
        }
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out") { Task { await model.signOut() } }
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            AsyncButton("Delete account and all my data", role: .destructive) {
                try await model.deleteAccount()
            }
        } message: {
            Text("This permanently removes your profile, visits, ratings, photos, saved places, custom ranking systems and follows. It can't be undone.")
        }
    }
}

struct StatTile: View {
    var value: Int
    var label: String
    var symbol: String
    var fill: LinearGradient

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).font(.subheadline).foregroundStyle(.white.opacity(0.85)).accessibilityHidden(true)
            Text("\(value)").font(.display(.title, weight: .bold)).foregroundStyle(Theme.alabaster).contentTransition(.numericText())
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.92))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(fill, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: Theme.jet.opacity(0.16), radius: 10, y: 5)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsRow: View {
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.alabaster)
                .frame(width: 30, height: 30)
                .background(Theme.roseGradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
            Spacer()
            Text(detail).font(.subheadline).foregroundStyle(Theme.inkSoft)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

struct EditProfileSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var username = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Display name", text: $displayName)
                }
                Section {
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Username")
                } footer: {
                    Text("3–24 characters: lowercase letters, numbers, dots and underscores. This is how people find you.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.warning) }
                }
            }
            .navigationTitle("Edit profile")
            .modalSurface()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(isSaving || displayName.isBlank || username.trimmed.count < 3)
                }
            }
            .onAppear {
                displayName = model.profile?.displayName ?? ""
                username = model.profile?.username ?? ""
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let cleaned = username.trimmed.lowercased()
        guard cleaned.range(of: "^[a-z0-9_.]{3,24}$", options: .regularExpression) != nil else {
            errorMessage = "Usernames are 3–24 characters: lowercase letters, numbers, dots and underscores."
            return
        }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await model.updateProfile {
                    $0.displayName = displayName.trimmed
                    $0.username = cleaned
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct VisitedListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let ranked = model.ranked(scope: .allSystems)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if ranked.isEmpty {
                    EmptyState(symbol: "checkmark.circle", title: "No visits yet",
                               message: "Restaurants appear here once you've submitted a rating for them.").card()
                }
                ForEach(ranked.sorted { RankingEngine.isLater($0.visit, than: $1.visit) }) { entry in
                    if let ref = model.restaurants[entry.restaurantID] {
                        NavigationLink(value: Route.restaurant(placeID: ref.providerPlaceID)) {
                            SavedRestaurantRow(
                                restaurantID: entry.restaurantID,
                                trailing: AnyView(ScoreBadge(total: entry.total, systemName: model.systemName(entry.revision.systemID), size: .compact)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !ranked.isEmpty {
                    Text("Most recent first. Each score is labelled with the system it was made with.")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(Theme.spacing)
        }
        .screenBackground()
        .navigationTitle("Visited")
    }
}

struct SavedListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if model.saved.isEmpty {
                    EmptyState(symbol: "bookmark", title: "Nothing saved",
                               message: "Save a restaurant from Discover or the map to keep it on your want-to-try list.").card()
                }
                if let error = model.placeLoadError {
                    ErrorBanner(message: error.localizedDescription, retry: error.isRetryable ? { model.retryPlaceLoads() } : nil)
                }
                ForEach(model.saved.sorted { $0.savedAt > $1.savedAt }, id: \.restaurantID) { saved in
                    if let ref = model.restaurants[saved.restaurantID] {
                        NavigationLink(value: Route.restaurant(placeID: ref.providerPlaceID)) {
                            SavedRestaurantRow(restaurantID: saved.restaurantID)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Theme.spacing)
        }
        .screenBackground()
        .navigationTitle("Want to try")
    }
}

/// Request monitoring: what this device has asked the places provider for today, and the
/// local caps that stop a bug or a runaway loop from running up a bill.
struct UsageView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let monitor = model.environment.monitor
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                if model.isDemo {
                    Label("Demo mode: these are simulated requests. Nothing is sent to Google and nothing is billed.", systemImage: "theatermasks")
                        .font(.footnote).foregroundStyle(Theme.warning)
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Today", detail: "\(monitor.todayTotal) of \(monitor.limits.perDay) allowed on this device")
                    ProgressView(value: Double(min(monitor.todayTotal, monitor.limits.perDay)), total: Double(monitor.limits.perDay))
                        .tint(monitor.todayTotal >= monitor.limits.perDay ? Theme.warning : Theme.seagrass)
                    ForEach(PlacesRequestKind.allCases) { kind in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(kind.title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                                Text(kind.sku).font(.caption).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer()
                            Text("\(monitor.todayCounts[kind] ?? 0)").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.ink)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("Limits")
                    LabeledRow(symbol: "timer", text: "\(monitor.limits.perMinute) requests per minute")
                    LabeledRow(symbol: "calendar", text: "\(monitor.limits.perDay) requests per day")
                    LabeledRow(symbol: "hand.raised", text: "\(monitor.blockedToday) blocked today")
                    if let error = monitor.lastProviderError {
                        LabeledRow(symbol: "exclamationmark.triangle", text: "Last provider error: \(error)")
                    }
                    Text("Set in Config/App.xcconfig. These are a safety net on the device; real spending limits belong in Google Cloud quotas.")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                }
                .card()
            }
            .padding(Theme.spacing)
        }
        .screenBackground()
        .navigationTitle("Search usage")
    }
}

struct LegalView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("Restaurant listings")
                    Text(model.isDemo
                         ? "This build is running in demo mode. Every restaurant listing and person is fictional and none comes from Google."
                         : "Restaurant names, addresses and locations are provided by Google Maps and shown under the Google Maps Platform terms. Only the place ID is stored with your account; listing details are fetched when needed and not kept.")
                        .font(.subheadline).foregroundStyle(Theme.inkSoft)
                    if !model.isDemo {
                        Link("Google Maps/Google Earth Additional Terms of Service", destination: URL(string: "https://maps.google.com/help/terms_maps.html")!)
                        Link("Google Privacy Policy", destination: URL(string: "https://policies.google.com/privacy")!)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("Your content")
                    Text("Scores, notes, dishes, photos and ranking systems are yours. They are stored separately from provider listings and are removed when you delete them or your account.")
                        .font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
                .card()

                if !model.isDemo {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle("Open source licences")
                        Text(GMSServices.openSourceLicenseInfo())
                            .font(.caption2.monospaced())
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .card()
                }
            }
            .padding(Theme.spacing)
        }
        .screenBackground()
        .navigationTitle("About")
    }
}
