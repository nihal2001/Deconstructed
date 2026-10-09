import SwiftUI

struct RestaurantProfileView: View {
    @Environment(AppModel.self) private var model
    var placeID: String

    @State private var community: [CommunityScore]?
    @State private var communityError: String?
    @State private var showLogVisit = false
    @State private var isLoadingMore = false

    private var place: Place? { model.places[placeID] }
    private var visits: [Visit] { model.visits(forPlaceID: placeID) }
    private var latestCompleted: Visit? { visits.first(where: \.isCompleted) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let error = model.placeLoadError, place?.name == nil {
                    ErrorBanner(message: error.localizedDescription,
                                retry: error.isRetryable ? { model.retryPlaceLoads() } : nil)
                }
                actions
                yourScore
                history
                communitySection
                listing
            }
            .padding(Theme.spacing)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.placeReloadToken) {
            await model.ensurePlace(placeID, level: .core)
        }
        .task(id: visits.map(\.updatedAt)) {
            await loadCommunity()
        }
        .sheet(isPresented: $showLogVisit) {
            if let place { LogVisitView(place: place, existing: nil) }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(place?.name ?? "Restaurant")
                    .font(.display(.largeTitle, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .redacted(reason: place?.name == nil && model.placeLoadError == nil ? .placeholder : [])
                if place?.isDemo == true { DemoBadge() }
            }
            if let subtitle = place?.subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.title3).foregroundStyle(Theme.inkSoft)
            }
            PlaceStatusTags(placeID: placeID)
        }
        .hero()
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                showLogVisit = true
            } label: {
                Label("Log a visit", systemImage: "square.and.pencil")
            }
            .buttonStyle(.primary)
            .disabled(place == nil)

            HStack(spacing: 10) {
                let isSaved = model.isSaved(placeID: placeID)
                AsyncButton {
                    guard let place else { return }
                    try await model.setSaved(place, saved: !isSaved)
                } label: {
                    Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(.secondary(tint: isSaved ? Theme.olive : Theme.ink))
                .disabled(place == nil)
                .accessibilityLabel(isSaved ? "Saved to Want to try. Tap to remove." : "Save to Want to try")

                Button {
                    model.showOnMap(placeID: placeID)
                } label: {
                    Label("View on map", systemImage: "map")
                }
                .buttonStyle(.secondary)
                .disabled(place?.coordinate == nil)
            }
        }
    }

    @ViewBuilder
    private var yourScore: some View {
        SectionTitle("Your score", detail: latestCompleted == nil ? nil : "From your most recent completed visit")
        if let visit = latestCompleted, let revision = visit.activeRevision {
            NavigationLink(value: Route.visit(visit, author: nil)) {
                VStack(alignment: .leading, spacing: 10) {
                    RatingSummary(revision: revision, size: .large)
                    Text("Visited \(visit.visitedOn.visitFormatted)")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                }
                .card()
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("You haven't scored this place yet.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Log a visit to score it criterion by criterion. The total is worked out for you.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
            }
            .card()
        }
    }

    @ViewBuilder
    private var history: some View {
        if !visits.isEmpty {
            SectionTitle("Visit history", detail: "\(visits.count) visit\(visits.count == 1 ? "" : "s"). Earlier scores are kept as they were.")
            VStack(spacing: 0) {
                ForEach(visits) { visit in
                    NavigationLink(value: Route.visit(visit, author: nil)) {
                        VisitHistoryRow(visit: visit, isLatest: visit.id == latestCompleted?.id)
                    }
                    .buttonStyle(.plain)
                    if visit.id != visits.last?.id { Divider() }
                }
            }
            .card(padding: 14)
        }
    }

    @ViewBuilder
    private var communitySection: some View {
        SectionTitle("Community", detail: "Averages of other people's public ratings. Separate from your own score.")
        if let community {
            if community.isEmpty {
                Text("No public ratings yet with a standard system.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                    .card()
            } else {
                ForEach(community) { CommunityScoreCard(score: $0) }
                Text("Each person counts once, through their latest visit. Systems and versions are averaged separately because they measure different things. Custom systems appear on individual reviews only.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
        } else if let communityError {
            ErrorBanner(message: communityError) { Task { await loadCommunity() } }
        } else {
            ProgressView().frame(maxWidth: .infinity).padding()
        }
    }

    @ViewBuilder
    private var listing: some View {
        if let place {
            SectionTitle("About this place")
            VStack(alignment: .leading, spacing: 10) {
                if let address = place.address { LabeledRow(symbol: "mappin", text: address) }
                if let price = place.priceLevel {
                    LabeledRow(symbol: "banknote", text: String(repeating: "$", count: price))
                        .accessibilityLabel("Price level \(price) of 4")
                }
                if let phone = place.phone { LabeledRow(symbol: "phone", text: phone) }
                if let website = place.website {
                    Link(destination: website) { LabeledRow(symbol: "safari", text: website.host() ?? "Website") }
                }
                ForEach(place.openingHours, id: \.self) { line in
                    Text(line).font(.footnote).foregroundStyle(Theme.inkSoft)
                }
                if place.level < .extended {
                    // Hours and contact details are a pricier request, so they wait for a tap.
                    Button {
                        isLoadingMore = true
                        Task {
                            await model.ensurePlace(placeID, level: .extended)
                            isLoadingMore = false
                        }
                    } label: {
                        HStack {
                            Label("Show hours and contact details", systemImage: "clock")
                            if isLoadingMore { ProgressView() }
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(isLoadingMore)
                }
                Divider()
                ProviderAttribution(isDemo: place.isDemo, thirdParty: place.thirdPartyAttribution)
            }
            .card()
        }
    }

    private func loadCommunity() async {
        do {
            let scores = try await model.communityScores(placeID: placeID)
            community = scores
            communityError = nil
        } catch {
            if community == nil { communityError = error.localizedDescription }
        }
    }
}

struct VisitHistoryRow: View {
    @Environment(AppModel.self) private var model
    var visit: Visit
    var isLatest: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(visit.visitedOn.visitFormatted)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let revision = visit.activeRevision {
                    ScoreBadge(total: revision.total, systemName: model.systemName(revision.systemID), size: .compact)
                } else {
                    Tag(text: "Draft · not ranked", symbol: "pencil", tone: .warning)
                }
            }
            Spacer()
            if isLatest { Tag(text: "Counts in rankings", tone: .seagrass) }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSoft)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
