import SwiftUI

/// Personal rankings. One system and version at a time by default, because totals from
/// different rubrics measure different things.
struct RankingsView: View {
    @Environment(AppModel.self) private var model

    private enum Choice: Hashable {
        case all
        case system(UUID)
    }

    @State private var choice: Choice?
    @State private var versionOverride: UUID?
    @State private var cuisine: String?
    @State private var area: String?

    // MARK: Derived state

    /// Systems worth offering: anything selectable, plus archived ones that still hold ratings.
    private var systemOptions: [RankingSystem] {
        model.mySystems.filter { $0.currentVersionID != nil && (!model.isArchived($0) || model.hasRatings($0)) }
    }

    private var resolvedChoice: Choice {
        if let choice { return choice }
        return model.defaultSystem.map { .system($0.id) } ?? .all
    }

    private var selectedSystem: RankingSystem? {
        if case .system(let id) = resolvedChoice { return model.systems[id] }
        return nil
    }

    /// Versions of the selected system that have at least one of your ratings, plus the current one.
    private var versionOptions: [SystemVersion] {
        guard let system = selectedSystem else { return [] }
        let used = Set(model.visits.compactMap(\.activeRevision).filter { $0.systemID == system.id }.map(\.versionID))
        return model.versions(of: system.id).filter { used.contains($0.id) || $0.id == system.currentVersionID }
    }

    private var selectedVersion: SystemVersion? {
        versionOptions.first { $0.id == versionOverride } ?? versionOptions.first { $0.id == selectedSystem?.currentVersionID }
            ?? versionOptions.first
    }

    private var scope: SystemScope {
        if let system = selectedSystem, let version = selectedVersion {
            return .version(systemID: system.id, versionID: version.id)
        }
        return .allSystems
    }

    private var unfiltered: [RankedRestaurant] { model.ranked(scope: scope) }

    private var ranked: [RankedRestaurant] {
        guard cuisine != nil || area != nil else { return unfiltered }
        let allowed = Set(unfiltered.map(\.restaurantID).filter { id in
            let place = model.place(for: id)
            return (cuisine == nil || place?.cuisine == cuisine) && (area == nil || place?.area == area)
        })
        return RankingEngine.rank(visits: model.visits.filter { allowed.contains($0.restaurantID) }, scope: scope) {
            model.place(for: $0)?.name ?? ""
        }
    }

    private var cuisines: [String] {
        Array(Set(unfiltered.compactMap { model.place(for: $0.restaurantID)?.cuisine })).sorted()
    }

    private var areas: [String] {
        Array(Set(unfiltered.compactMap { model.place(for: $0.restaurantID)?.area })).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    scopeCard
                    if let error = model.placeLoadError {
                        ErrorBanner(message: error.localizedDescription,
                                    retry: error.isRetryable ? { model.retryPlaceLoads() } : nil)
                    }
                    if !cuisines.isEmpty || !areas.isEmpty { filters }

                    if ranked.isEmpty {
                        EmptyState(
                            symbol: "list.number",
                            title: unfiltered.isEmpty ? "Nothing ranked here yet" : "No matches",
                            message: unfiltered.isEmpty
                                ? "Completed visits scored with \(selectedSystem?.name ?? "any system") show up here. Drafts don't count until you submit them."
                                : "No ranked restaurants match these filters.")
                            .card()
                    } else {
                        VStack(spacing: 10) {
                            ForEach(ranked) { entry in
                                if let ref = model.restaurants[entry.restaurantID] {
                                    NavigationLink(value: Route.restaurant(placeID: ref.providerPlaceID)) {
                                        RankedRow(entry: entry, showsSystem: scope == .allSystems)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if ranked.contains(where: \.isTied) {
                            Text("Equal totals share a rank. Tied restaurants are simply listed A–Z; no hidden tiebreaker decides between them.")
                                .font(.caption).foregroundStyle(Theme.inkSoft)
                        }
                        Text("Each restaurant is ranked by your most recent completed visit\(scope == .allSystems ? "" : " scored with this system and version"). Earlier visits stay in its history.")
                            .font(.caption).foregroundStyle(Theme.inkSoft)
                    }

                    drafts
                }
                .padding(Theme.spacing)
            }
            .screenBackground()
            .navigationTitle("Rankings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: Route.rankingSystems) {
                        Label("Ranking systems", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .appRoutes()
            .task(id: "\(model.visits.count)-\(model.placeReloadToken)") {
                // Names are needed for the list and for A–Z order inside ties.
                for id in model.visitedRestaurantIDs.union(model.draftVisits.map(\.restaurantID)) {
                    guard !Task.isCancelled else { return }
                    await model.ensurePlace(for: id)
                }
            }
        }
    }

    // MARK: Sections

    private var scopeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RANKED WITH").font(.dataKey).tracking(0.8).foregroundStyle(Theme.inkSoft)
                Spacer()
                Menu {
                    Picker("System", selection: Binding(get: { resolvedChoice }, set: { newValue in
                        choice = newValue
                        versionOverride = nil
                    })) {
                        ForEach(systemOptions) { system in
                            Text(model.isArchived(system) ? "\(system.name) (archived)" : system.name).tag(Choice.system(system.id))
                        }
                        Text("All systems").tag(Choice.all)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedSystem?.name ?? "All systems").font(.display(.title3))
                        Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Theme.ink)
                }
                .accessibilityLabel("Ranking system: \(selectedSystem?.name ?? "All systems")")
            }

            if let version = selectedVersion {
                if versionOptions.count > 1 {
                    SegmentedChips(title: "Version", options: versionOptions.map(\.id),
                                   selection: Binding(get: { version.id }, set: { versionOverride = $0 })) { id in
                        let option = versionOptions.first { $0.id == id }
                        return "Version \(option?.number ?? 0)\(id == selectedSystem?.currentVersionID ? " · current" : "")"
                    }
                    Text("Versions are ranked separately because their criteria differ. Re-rate a visit to move it to another version.")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                }
                AllocationStrip(criteria: version.criteria)
            } else {
                Label("Different systems emphasise different qualities, so an 8 in one isn't the same as an 8 in another. Every score below is labelled with the system that produced it.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .hero()
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterMenu(title: "Cuisine", options: cuisines, selection: $cuisine)
                FilterMenu(title: "Area", options: areas, selection: $area)
            }
        }
    }

    @ViewBuilder
    private var drafts: some View {
        if !model.draftVisits.isEmpty {
            SectionTitle("Drafts", detail: "Unfinished ratings. Not ranked until submitted.")
            ForEach(model.draftVisits) { visit in
                NavigationLink(value: Route.visit(visit, author: nil)) {
                    SavedRestaurantRow(restaurantID: visit.restaurantID,
                                       trailing: AnyView(Tag(text: "Draft", symbol: "pencil", tone: .warning)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct RankedRow: View {
    @Environment(AppModel.self) private var model
    var entry: RankedRestaurant
    /// Under "All systems" each score carries the name of the system that produced it.
    var showsSystem = false

    /// The podium places get an ink each. Tied ranks share one, like the rank itself.
    private var medal: Color {
        switch entry.rank {
        case 1: Theme.tomato
        case 2: Theme.teal
        case 3: Theme.ultramarine
        default: Theme.plate
        }
    }

    var body: some View {
        let place = model.place(for: entry.restaurantID)
        let systemName = model.systemName(entry.revision.systemID)
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Text("\(entry.rank)")
                    .font(.display(.title3, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Theme.text(on: medal))
                    .frame(width: 40, height: 40)
                    .background(medal, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.rule, lineWidth: Theme.ruleWidth) }
                if entry.isTied {
                    Text("tied").font(.caption2.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.displayName(for: entry.restaurantID))
                        .font(.display(.headline))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    if place?.isDemo == true { DemoBadge() }
                }
                if let subtitle = place?.subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.footnote).foregroundStyle(Theme.inkSoft)
                }
                if let version = model.versions[entry.revision.versionID] {
                    ScoreBar(version: version, scores: entry.revision.scores, height: 8)
                        .padding(.top, 2)
                }
                if entry.completedVisitCount > 1 {
                    Text("\(entry.completedVisitCount) visits · latest \(entry.visit.visitedOn.visitFormatted)")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(entry.total)")
                        .font(.display(.title, weight: .heavy).monospacedDigit())
                        .tracking(-1)
                        .foregroundStyle(Theme.ink)
                    Text("/\(RankingRules.totalPoints)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.inkSoft)
                }
                if showsSystem {
                    Text(systemName).font(.caption2.weight(.semibold)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
            }
            .fixedSize()
        }
        // Only the podium casts a shadow, in its own ink, so the top three lift off the list.
        .card(padding: 14, shadow: entry.rank <= 3 ? medal : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rank \(entry.rank)\(entry.isTied ? ", tied" : ""). \(model.displayName(for: entry.restaurantID)). \(entry.total) out of 10, \(systemName) system.")
        .accessibilityHint("Opens the restaurant")
    }
}

struct FilterMenu: View {
    var title: String
    var options: [String]
    @Binding var selection: String?

    var body: some View {
        if !options.isEmpty {
            Menu {
                Picker(title, selection: $selection) {
                    Text("Any \(title.lowercased())").tag(String?.none)
                    ForEach(options, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selection ?? title)
                    Image(systemName: "chevron.down").imageScale(.small)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selection == nil ? Theme.ink : Theme.onTint)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(selection == nil ? Theme.plate : Theme.tint, in: Capsule())
                .overlay { Capsule().strokeBorder(Theme.rule, lineWidth: 1.5) }
            }
            .accessibilityLabel("\(title) filter: \(selection ?? "any")")
        }
    }
}
