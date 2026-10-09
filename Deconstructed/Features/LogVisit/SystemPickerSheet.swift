import SwiftUI

/// Choose the rubric for a rating. Each option shows its name, what it is for and how its
/// ten points are split, so the choice is informed before any scoring happens.
struct SystemPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var selectedSystemID: UUID?
    var onSelect: (RankingSystem) -> Void

    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pick the system that fits the kind of place. Different systems weigh different things, so a score always shows which one produced it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)

                    ForEach(model.selectableSystems) { system in
                        Button {
                            onSelect(system)
                            dismiss()
                        } label: {
                            SystemOptionCard(system: system, isSelected: system.id == selectedSystemID)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(system.id == selectedSystemID ? .isSelected : [])
                    }

                    Button {
                        showEditor = true
                    } label: {
                        Label("Add new ranking system", systemImage: "plus")
                    }
                    .buttonStyle(.secondary(tint: Theme.rose))
                    .padding(.top, 4)
                }
                .padding(Theme.spacing)
            }
            .screenBackground()
            .navigationTitle("Ranking system")
            .modalSurface()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showEditor) {
                SystemEditorView(system: nil) { created in
                    // A newly activated system is selected straight away.
                    if created.isSelectableForNewRatings {
                        onSelect(created)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SystemOptionCard: View {
    @Environment(AppModel.self) private var model
    var system: RankingSystem
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(system.name).font(.display(.title3)).foregroundStyle(Theme.ink)
                SystemKindTag(system: system)
                if model.defaultSystem?.id == system.id { Tag(text: "Default", symbol: "star.fill", tone: .rose) }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.rose).font(.title3)
                        .accessibilityHidden(true)
                }
            }
            if !system.summary.isBlank {
                Text(system.summary)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.leading)
            }
            if let version = model.currentVersion(of: system) {
                AllocationStrip(criteria: version.criteria)
            }
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .environment(\.colorScheme, .light)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(isSelected ? Theme.rose : Theme.hairline.opacity(0.7), lineWidth: isSelected ? 2 : 1)
        }
    }
}

/// Says whether ratings with this system can join community averages.
struct SystemKindTag: View {
    var system: RankingSystem

    var body: some View {
        if system.isStandard {
            Tag(text: "Standard", tone: .seagrass)
                .accessibilityLabel("Standard system. Public ratings count toward community scores.")
        } else {
            Tag(text: "Custom", tone: .olive)
                .accessibilityLabel("Custom system. Ratings are yours alone and don't join community scores.")
        }
    }
}
