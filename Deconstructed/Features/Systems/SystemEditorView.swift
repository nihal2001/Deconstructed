import SwiftUI

/// Create or edit a ranking system.
///
/// - Saving a draft is always allowed, however incomplete.
/// - Activating needs the criteria to total exactly 10 and every score to be described.
/// - Changing a criterion's maximum flags its descriptions for review before publishing.
/// - Publishing changed criteria creates a new version; existing ratings keep theirs.
struct SystemEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// The system being edited, or nil for a brand-new one.
    let system: RankingSystem?
    var onFinish: (RankingSystem) -> Void

    @State private var draft: SystemDraft = .blank
    @State private var original: SystemDraft = .blank
    @State private var didLoad = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmDiscard = false
    @State private var editingCriterionID: UUID?

    private var issues: [SystemIssue] { SystemValidator.issues(for: draft) }
    private var currentVersion: SystemVersion? { system.flatMap(model.currentVersion(of:)) }
    private var isStandard: Bool { system?.isStandard ?? false }
    private var hasChanges: Bool { draft != original }

    /// What pressing the main button will do, in the user's terms.
    private var publishTitle: String {
        guard let currentVersion, !isStandard else {
            return isStandard ? "Save as my copy" : "Activate system"
        }
        return SystemValidator.requiresNewVersion(draft, comparedTo: currentVersion)
            ? "Publish version \(nextVersionNumber)"
            : "Save changes"
    }

    private var nextVersionNumber: Int {
        (system.map { model.versions(of: $0.id).map(\.number).max() ?? 0 } ?? 0) + 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isStandard { forkNotice }
                    if let errorMessage { ErrorBanner(message: errorMessage) }
                    basics
                    allocation
                    criteriaSection
                    if !issues.isEmpty { checklist }
                    versionNote
                }
                .padding(Theme.spacing)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle(system == nil ? "New ranking system" : "Edit system")
            .modalSurface()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { confirmDiscard = true } else { dismiss() }
                    }
                    .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .navigationDestination(item: $editingCriterionID) { id in
                if let index = draft.criteria.firstIndex(where: { $0.id == id }) {
                    CriterionEditorView(criterion: $draft.criteria[index], color: Theme.criterionColor(index),
                                        pointsLeft: RankingRules.totalPoints - draft.allocatedPoints)
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .interactiveDismissDisabled(hasChanges || isSaving)
            .onAppear(perform: load)
        }
    }

    // MARK: Sections

    private var forkNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("You're editing a standard system", systemImage: "square.on.square")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("Saving creates your own copy of \(system?.name ?? "it") and puts the standard one away for you. The standard system itself, and everyone else's ratings, don't change. Ratings you make with your copy are shown on your reviews but aren't part of the standard community average.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(14)
        .background(Theme.olive.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var basics: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                TextField("e.g. Date Night, Ramen, Brunch", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("System name")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Description").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                TextField("What kind of place is this for, and what does it reward?", text: $draft.summary, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("System description")
            }
        }
        .card()
    }

    private var allocation: some View {
        let allocated = draft.allocatedPoints
        let balanced = allocated == RankingRules.totalPoints
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(allocated) of \(RankingRules.totalPoints) points allocated")
                    .font(.display(.title3))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Spacer()
                Image(systemName: balanced ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(balanced ? Theme.seagrass : Theme.warning)
                    .accessibilityHidden(true)
            }
            if !draft.criteria.isEmpty {
                AllocationStrip(criteria: draft.criteria)
            }
            Text(balanced
                 ? "Every system totals exactly 10."
                 : allocated < RankingRules.totalPoints
                     ? "\(RankingRules.totalPoints - allocated) point\(RankingRules.totalPoints - allocated == 1 ? "" : "s") left to give out."
                     : "\(allocated - RankingRules.totalPoints) point\(allocated - RankingRules.totalPoints == 1 ? "" : "s") over. Lower a maximum.")
                .font(.footnote)
                .foregroundStyle(balanced ? Theme.inkSoft : Theme.warning)
        }
        .card()
        .animation(.snappy, value: allocated)
        .accessibilityElement(children: .combine)
    }

    private var criteriaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Criteria", detail: "Whole-number maximums. Tap a criterion to describe each score.")
            ForEach(Array(draft.criteria.enumerated()), id: \.element.id) { index, criterion in
                criterionRow(criterion, index: index)
            }
            Button {
                let remaining = max(1, RankingRules.totalPoints - draft.allocatedPoints)
                let criterion = Criterion.blank(maxPoints: min(remaining, 2))
                withAnimation(.snappy) { draft.criteria.append(criterion) }
                editingCriterionID = criterion.id
            } label: {
                Label("Add criterion", systemImage: "plus")
            }
            .buttonStyle(.secondary(tint: Theme.rose))
        }
    }

    private func criterionRow(_ criterion: Criterion, index: Int) -> some View {
        let problems = issues.filter { $0.criterionID == criterion.id }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(Theme.criterionColor(index)).frame(width: 10, height: 10).accessibilityHidden(true)
                Button {
                    editingCriterionID = criterion.id
                } label: {
                    HStack(spacing: 6) {
                        Text(criterion.name.isBlank ? "Unnamed criterion" : criterion.name)
                            .font(.display(.headline))
                            .foregroundStyle(criterion.name.isBlank ? Theme.inkSoft : Theme.ink)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.inkSoft)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edit name and score descriptions")
                Spacer(minLength: 4)
                Menu {
                    Button("Move up", systemImage: "arrow.up") { move(index, by: -1) }.disabled(index == 0)
                    Button("Move down", systemImage: "arrow.down") { move(index, by: 1) }
                        .disabled(index == draft.criteria.count - 1)
                    Button("Remove criterion", systemImage: "trash", role: .destructive) {
                        withAnimation(.snappy) { draft.criteria.removeAll { $0.id == criterion.id } }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Theme.inkSoft)
                        .frame(width: 44, height: 32)
                }
                .accessibilityLabel("Reorder or remove \(criterion.name.isBlank ? "criterion" : criterion.name)")
            }

            Stepper(value: Binding(
                get: { criterion.maxPoints },
                set: { newValue in
                    if let i = draft.criteria.firstIndex(where: { $0.id == criterion.id }) {
                        draft.criteria[i].setMaxPoints(newValue)
                    }
                }), in: 1...RankingRules.totalPoints) {
                Text("Maximum: \(criterion.maxPoints) point\(criterion.maxPoints == 1 ? "" : "s")")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityValue("\(criterion.maxPoints)")

            ForEach(problems) { problem in
                Label(rowMessage(for: problem), systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
        }
        .card(padding: 14)
    }

    private func rowMessage(for issue: SystemIssue) -> String {
        switch issue {
        case .needsReview: "Maximum changed. Review the score descriptions."
        case .missingDescriptions(_, _, let points): "Missing description for \(points.map(String.init).joined(separator: ", "))."
        case .criterionMissingName: "Needs a name."
        default: issue.message
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Before this can be \(currentVersion == nil ? "activated" : "published")")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            ForEach(issues) { issue in
                Label(issue.message, systemImage: "circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
            }
            Text("You can save it as a draft in the meantime.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
        }
        .card()
    }

    @ViewBuilder
    private var versionNote: some View {
        if let currentVersion, !isStandard, SystemValidator.requiresNewVersion(draft, comparedTo: currentVersion) {
            Label("Publishing creates version \(nextVersionNumber) for future ratings. Ratings already made keep version \(currentVersion.number), with its criteria and descriptions, and are not recalculated. You can re-rate a visit with the new version whenever you choose.",
                  systemImage: "clock.arrow.circlepath")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(isSaving ? "Saving…" : "Save draft") { save(publish: false) }
                .buttonStyle(.secondary)
                .disabled(isSaving || !hasChanges)
            Button(publishTitle) { save(publish: true) }
                .buttonStyle(.primary)
                // An untouched copy of a standard system would only take it out of community averages.
                .disabled(isSaving || !issues.isEmpty || (isStandard && !hasChanges))
                .accessibilityHint(issues.isEmpty ? "" : "Complete the checklist first")
        }
        .padding(.horizontal, Theme.spacing)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: Actions

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let system {
            draft = system.editableDraft(currentVersion: currentVersion)
            original = draft
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard draft.criteria.indices.contains(target) else { return }
        withAnimation(.snappy) { draft.criteria.swapAt(index, target) }
    }

    private func save(publish: Bool) {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                let saved: RankingSystem
                if publish {
                    saved = try await model.publishSystem(draft, for: system)
                    let number = model.currentVersion(of: saved)?.number ?? 1
                    model.toast = isStandard
                        ? "Saved your copy of \(saved.name)"
                        : number > 1 ? "\(saved.name) is now on version \(number)" : "\(saved.name) is ready to use"
                } else {
                    saved = try await model.saveSystemDraft(draft, for: system)
                    model.toast = "Draft saved"
                }
                onFinish(saved)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Edit one criterion: its name, its maximum and what every selectable score means.
struct CriterionEditorView: View {
    @Binding var criterion: Criterion
    var color: Color
    /// Unallocated points in the whole system, for guidance only.
    var pointsLeft: Int

    private var missing: [Int] {
        criterion.levels.filter(\.detail.isBlank).map(\.points)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Criterion name").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                        TextField("e.g. Food, Service, Broth", text: $criterion.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What it covers").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                        TextField("A sentence on what to judge", text: $criterion.guidance, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.roundedBorder)
                    }
                    Stepper(value: Binding(get: { criterion.maxPoints }, set: { criterion.setMaxPoints($0) }),
                            in: 1...RankingRules.totalPoints) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Maximum: \(criterion.maxPoints) point\(criterion.maxPoints == 1 ? "" : "s")")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text(pointsLeft == 0 ? "All 10 points are allocated."
                                 : pointsLeft > 0 ? "\(pointsLeft) unallocated in this system."
                                 : "\(-pointsLeft) over the total of 10.")
                                .font(.caption)
                                .foregroundStyle(pointsLeft == 0 ? Theme.inkSoft : Theme.warning)
                        }
                    }
                }
                .card()

                if criterion.needsLevelReview {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("The maximum changed", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.warning)
                        Text("A score of 2 means something different out of \(criterion.maxPoints) than it did before. Read through each description below and adjust it, then confirm.")
                            .font(.footnote)
                            .foregroundStyle(Theme.ink)
                        Button("I've reviewed these descriptions") {
                            withAnimation(.snappy) { criterion.needsLevelReview = false }
                        }
                        .buttonStyle(.secondary(tint: Theme.warning))
                        .disabled(!missing.isEmpty)
                        if !missing.isEmpty {
                            Text("Describe every score first.").font(.caption).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .padding(14)
                    .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                SectionTitle("What each score means", detail: "People choose one of these when rating, so be specific.")
                ForEach($criterion.levels) { $level in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text("\(level.points)")
                                .font(.display(.title3, weight: .bold).monospacedDigit())
                                .foregroundStyle(Theme.alabaster)
                                .frame(minWidth: 36, minHeight: 36)
                                .background(color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .accessibilityLabel("\(level.points) point\(level.points == 1 ? "" : "s")")
                            TextField("Short label (optional)", text: $level.label)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Label for \(level.points) points")
                        }
                        TextField("Describe what earns \(level.points) out of \(criterion.maxPoints)", text: $level.detail, axis: .vertical)
                            .lineLimit(2...5)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Description for \(level.points) points")
                        if level.detail.isBlank {
                            Label("Needs a description", systemImage: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(Theme.warning)
                        }
                    }
                    .card(padding: 14)
                }
            }
            .padding(Theme.spacing)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle(criterion.name.isBlank ? "Criterion" : criterion.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
