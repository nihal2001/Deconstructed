import SwiftUI

/// The ranking system manager: choose a default, edit, duplicate, archive and create systems.
struct RankingSystemsView: View {
    @Environment(AppModel.self) private var model
    @State private var showNewEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Text("A ranking system splits 10 points across criteria and says what each score means. Pick the one that suits the place you're rating.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)

                Button {
                    showNewEditor = true
                } label: {
                    Label("Add new ranking system", systemImage: "plus")
                }
                .buttonStyle(.primary)

                SectionTitle("Active", detail: "Available when you rate a visit")
                ForEach(model.selectableSystems) { system in
                    NavigationLink(value: Route.system(system.id)) {
                        SystemOptionCard(system: system)
                    }
                    .buttonStyle(.plain)
                }

                if !model.draftSystems.isEmpty {
                    SectionTitle("Drafts", detail: "Not usable until every criterion and description is complete")
                    ForEach(model.draftSystems) { system in
                        NavigationLink(value: Route.system(system.id)) {
                            DraftSystemCard(system: system)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !model.archivedSystems.isEmpty {
                    SectionTitle("Archived", detail: "Kept so past ratings stay readable. Can't be chosen for new ratings.")
                    ForEach(model.archivedSystems) { system in
                        NavigationLink(value: Route.system(system.id)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(system.name).font(.display(.headline)).foregroundStyle(Theme.ink)
                                    SystemKindTag(system: system)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                            }
                            .card(padding: 14)
                            .opacity(0.8)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Standard systems are shared by everyone, which is what makes community averages possible. Editing one gives you a personal copy; the original, and everyone else's ratings, are untouched.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(Theme.spacing)
        }
        .screenBackground()
        .navigationTitle("Ranking Systems")
        .sheet(isPresented: $showNewEditor) {
            SystemEditorView(system: nil) { _ in }
        }
    }
}

struct DraftSystemCard: View {
    var system: RankingSystem

    var body: some View {
        let draft = system.draft ?? .blank
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(system.name).font(.display(.headline)).foregroundStyle(Theme.ink)
                Tag(text: "Draft", symbol: "pencil", tone: .warning)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSoft)
            }
            Text("\(draft.allocatedPoints) of \(RankingRules.totalPoints) points allocated")
                .font(.footnote.weight(.medium))
                .foregroundStyle(draft.allocatedPoints == RankingRules.totalPoints ? Theme.seagrass : Theme.warning)
            if !draft.criteria.isEmpty { AllocationStrip(criteria: draft.criteria) }
        }
        .card(padding: 14)
    }
}

struct SystemDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var systemID: UUID

    @State private var editing: RankingSystem?
    @State private var confirmDelete = false
    @State private var confirmArchive = false

    var body: some View {
        ScrollView {
            if let system = model.systems[systemID] {
                content(system)
                    .padding(Theme.spacing)
            } else {
                EmptyState(symbol: "questionmark.circle", title: "System not found", message: "It may have been deleted.")
            }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { system in
            SystemEditorView(system: system) { _ in }
        }
    }

    @ViewBuilder
    private func content(_ system: RankingSystem) -> some View {
        let current = model.currentVersion(of: system)
        let archived = model.isArchived(system)
        let isDefault = model.defaultSystem?.id == system.id
        let versions = model.versions(of: system.id)

        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(system.name).font(.display(.largeTitle, weight: .bold)).foregroundStyle(Theme.ink)
                FlowLayout(spacing: 6) {
                    SystemKindTag(system: system)
                    if isDefault { Tag(text: "Default", symbol: "star.fill", tone: .rose) }
                    if archived { Tag(text: "Archived", symbol: "archivebox") }
                    if system.isDraftOnly { Tag(text: "Draft", symbol: "pencil", tone: .warning) }
                    if let current { Tag(text: "Version \(current.number)") }
                }
                if !system.summary.isBlank {
                    Text(system.summary).font(.body).foregroundStyle(Theme.inkSoft)
                }
            }

            if system.draft != nil, !system.isStandard {
                VStack(alignment: .leading, spacing: 10) {
                    Label(system.isDraftOnly ? "This system is a draft" : "You have unpublished edits", systemImage: "pencil.and.outline")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(system.isDraftOnly
                         ? "Finish its criteria and score descriptions, then activate it to use it for ratings."
                         : "Ratings keep using version \(current?.number ?? 1) until you publish the edits.")
                        .font(.footnote).foregroundStyle(Theme.inkSoft)
                    Button("Continue editing") { editing = system }.buttonStyle(.secondary)
                }
                .card()
            }

            actions(system, archived: archived, isDefault: isDefault)

            if let current {
                SectionTitle("Criteria", detail: "10 points in total")
                AllocationStrip(criteria: current.criteria).card()
                ForEach(Array(current.criteria.enumerated()), id: \.element.id) { index, criterion in
                    CriterionDefinitionCard(criterion: criterion, color: Theme.criterionColor(index))
                }
            }

            if versions.count > 1 || model.hasRatings(system) {
                SectionTitle("Versions", detail: "Each rating keeps the version it was made with. Old ratings are never recalculated.")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(versions) { version in
                        let count = model.visits.filter { $0.activeRevision?.versionID == version.id }.count
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Version \(version.number)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                if version.id == system.currentVersionID { Tag(text: "Current", tone: .seagrass) }
                                Spacer()
                                Text("\(count) rating\(count == 1 ? "" : "s")").font(.footnote).foregroundStyle(Theme.inkSoft)
                            }
                            Text(version.allocationSummary).font(.footnote).foregroundStyle(Theme.inkSoft)
                            Text("Published \(version.publishedAt.visitFormatted)").font(.caption).foregroundStyle(Theme.inkSoft)
                        }
                        .padding(.vertical, 10)
                        if version.id != versions.last?.id { Divider() }
                    }
                }
                .card(padding: 14)
            }
        }
        .confirmationDialog("Delete “\(system.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            AsyncButton("Delete system", role: .destructive) {
                try await model.deleteSystem(system)
                dismiss()
            }
        } message: {
            Text("This system has no ratings, so it can be removed completely.")
        }
        .confirmationDialog("Archive “\(system.name)”?", isPresented: $confirmArchive, titleVisibility: .visible) {
            AsyncButton("Archive") { try await model.setArchived(system, archived: true) }
        } message: {
            Text("It won't be offered for new ratings. Ratings you've already made with it stay exactly as they are, and you can restore it at any time.")
        }
    }

    @ViewBuilder
    private func actions(_ system: RankingSystem, archived: Bool, isDefault: Bool) -> some View {
        VStack(spacing: 10) {
            if archived {
                AsyncButton {
                    try await model.setArchived(system, archived: false)
                } label: {
                    Label(system.isStandard ? "Restore standard system" : "Restore from archive", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.primary)
            } else {
                if system.currentVersionID != nil, !isDefault {
                    AsyncButton {
                        try await model.setDefaultSystem(system)
                        model.toast = "\(system.name) is now your default"
                    } label: {
                        Label("Use as my default", systemImage: "star")
                    }
                    .buttonStyle(.primary)
                }
                HStack(spacing: 10) {
                    Button {
                        editing = system
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.secondary)

                    AsyncButton {
                        editing = try await model.duplicateSystem(system)
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .buttonStyle(.secondary)
                }
                if model.selectableSystems.count > 1 || system.isDraftOnly {
                    Button {
                        confirmArchive = true
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .buttonStyle(.secondary)
                }
            }

            if !system.isStandard {
                if model.hasRatings(system) {
                    Text("This system has ratings, so it can be archived but not deleted.")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.secondary(tint: Theme.rose))
                }
            } else if !archived {
                Text("Editing a standard system makes a personal copy for you. Ratings made with your copy appear on your reviews but no longer count toward the standard community average.")
                    .font(.caption).foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A criterion with every selectable score and its meaning, read-only.
struct CriterionDefinitionCard: View {
    var criterion: Criterion
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
                Text(criterion.name).font(.display(.title3)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(criterion.maxPoints) point\(criterion.maxPoints == 1 ? "" : "s")")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.inkSoft)
            }
            if !criterion.guidance.isBlank {
                Text(criterion.guidance).font(.footnote).foregroundStyle(Theme.inkSoft)
            }
            ForEach(criterion.levels.sorted { $0.points > $1.points }) { level in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(level.points)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        .frame(minWidth: 26, minHeight: 26)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        if !level.label.isBlank {
                            Text(level.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        }
                        Text(level.detail).font(.footnote).foregroundStyle(Theme.inkSoft)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }
}
