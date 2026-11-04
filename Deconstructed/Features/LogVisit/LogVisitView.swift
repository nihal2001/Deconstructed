import PhotosUI
import SwiftUI

/// Log a new visit, finish a draft, or edit an existing visit.
///
/// One question per slide, swiped or advanced through, with nothing that scrolls vertically:
/// the visit (date and system), one slide per criterion, notes and photos, then a summary to
/// submit from. Picking a score moves straight on, so a visit takes one tap per criterion
/// plus three more: start, skip or continue past details, submit.
///
/// Scores can only be entered through the criteria of the chosen system. There is no field
/// for an overall number anywhere in this flow.
struct LogVisitView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let place: Place
    let existing: Visit?

    /// Whether the form is collecting scores or showing a completed rating that will be kept.
    private enum Mode: Equatable {
        case scoring
        case keeping(RatingRevision)
    }

    /// One slide of the flow.
    private enum Step: Hashable {
        case visit
        case criterion(Int)
        case details
        case summary
    }

    private enum Field: Hashable {
        case notes, dish, spend
    }

    @State private var mode: Mode
    @State private var step: Step = .visit
    @State private var advance: Task<Void, Never>?
    /// True while the pager animates to a slide it was sent to. A touch in that moment stops
    /// the paged TabView where it is while its selection has already moved on, so slides
    /// ignore touches until the move finishes.
    @State private var isMoving = false
    @State private var details: VisitDetails
    @State private var versionID: UUID?
    @State private var scores: [UUID: Int]
    @State private var dishDraft = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var newPhotos: [Data] = []
    @State private var removedPhotoIDs: Set<UUID> = []
    @State private var showSystemPicker = false
    @State private var pendingSystem: RankingSystem?
    @State private var confirmDelete = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didSetDefaults = false
    @FocusState private var focus: Field?

    init(place: Place, existing: Visit?) {
        self.place = place
        self.existing = existing
        _details = State(initialValue: existing.map(VisitDetails.init) ?? VisitDetails())
        if let draft = existing?.draftRevision {
            _mode = State(initialValue: .scoring)
            _versionID = State(initialValue: draft.versionID)
            _scores = State(initialValue: draft.scores)
        } else if let active = existing?.activeRevision {
            _mode = State(initialValue: .keeping(active))
            _versionID = State(initialValue: active.versionID)
            _scores = State(initialValue: [:])
        } else {
            _mode = State(initialValue: .scoring)
            _versionID = State(initialValue: nil)
            _scores = State(initialValue: [:])
        }
    }

    private var version: SystemVersion? { model.version(versionID) }
    private var system: RankingSystem? { version.flatMap { model.systems[$0.systemID] } }
    private var isComplete: Bool { version.map { RatingEngine.isComplete(scores: scores, version: $0) } ?? false }
    private var criteria: [Criterion] { mode == .scoring ? version?.criteria ?? [] : [] }

    private var steps: [Step] {
        [.visit] + criteria.indices.map(Step.criterion) + [.details, .summary]
    }
    private var stepIndex: Int { steps.firstIndex(of: step) ?? 0 }

    /// The first criterion still to score, or details once everything is scored.
    private var firstUnscoredStep: Step {
        criteria.firstIndex { scores[$0.id] == nil }.map(Step.criterion) ?? .details
    }

    private var missing: [(index: Int, criterion: Criterion)] {
        criteria.enumerated().filter { scores[$0.element.id] == nil }.map { ($0.offset, $0.element) }
    }

    private var keptPhotos: [VisitPhoto] {
        (existing?.photos ?? []).filter { !removedPhotoIDs.contains($0.id) }
    }

    private var hasDetails: Bool {
        !details.notes.isBlank || !details.dishes.isEmpty || details.spendPerPerson != nil
            || !newPhotos.isEmpty || !keptPhotos.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                if let errorMessage {
                    ErrorBanner(message: errorMessage).padding(.horizontal, Theme.spacing)
                }
                StepProgressHeader(title: title(for: step), dots: dots, current: stepIndex,
                                   total: mode == .scoring ? version.map { RatingEngine.runningTotal(scores: scores, version: $0) } : nil,
                                   go: { go(toIndex: $0) })
                    .padding(.horizontal, Theme.spacing + 4)

                // A paged TabView snaps to whole slides. Each slide is laid out to fit the
                // screen, so nothing scrolls vertically.
                TabView(selection: $step) {
                    ForEach(steps, id: \.self) { step in
                        slide(step)
                            .padding(.horizontal, Theme.spacing)
                            .padding(.bottom, 18)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .tag(step)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .allowsHitTesting(!isMoving)
            }
            .padding(.top, 8)
            // The keyboard covers the lower part of a slide rather than squashing it.
            .ignoresSafeArea(.keyboard)
            .screenBackground()
            .navigationTitle(existing == nil ? "Log a visit" : "Edit visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .interactiveDismissDisabled(isSaving)
            .onAppear(perform: setDefaults)
            .onChange(of: step) {
                advance?.cancel()
                focus = nil
            }
            .onChange(of: pickerItems) { loadPickedPhotos() }
            .sheet(isPresented: $showSystemPicker) {
                SystemPickerSheet(selectedSystemID: system?.id) { chosen in
                    choose(chosen)
                }
            }
            .confirmationDialog(
                "Switch to \(pendingSystem?.name ?? "this system")?",
                isPresented: Binding(get: { pendingSystem != nil }, set: { if !$0 { pendingSystem = nil } }),
                titleVisibility: .visible
            ) {
                Button("Switch and clear scores", role: .destructive) {
                    if let pendingSystem { apply(pendingSystem) }
                    pendingSystem = nil
                }
                Button("Keep \(system?.name ?? "current system")", role: .cancel) { pendingSystem = nil }
            } message: {
                Text("Each system has its own criteria, so the scores you've entered with \(system?.name ?? "the current system") can't be carried over. They'll be cleared and you'll score this visit again from scratch.")
            }
            .confirmationDialog("Delete this visit?", isPresented: $confirmDelete, titleVisibility: .visible) {
                AsyncButton("Delete visit", role: .destructive) {
                    if let existing { try await model.deleteVisit(existing) }
                    dismiss()
                }
            } message: {
                Text("Its scores, notes and photos are removed and your rankings update. This can't be undone.")
            }
        }
    }

    // MARK: Navigation

    private func title(for step: Step) -> String {
        switch step {
        case .visit: "The visit"
        case .criterion(let index): "\(index + 1) of \(criteria.count) · \(criteria[index].name)"
        case .details: "Notes and photos"
        case .summary: "Summary"
        }
    }

    private var dots: [StepDot] {
        steps.enumerated().map { index, step in
            switch step {
            case .visit:
                StepDot(id: index, symbol: "calendar", isDone: version != nil)
            case .criterion(let c):
                StepDot(id: index, color: Theme.criterionColor(c), isDone: scores[criteria[c].id] != nil)
            case .details:
                StepDot(id: index, symbol: "square.and.pencil", isDone: hasDetails)
            case .summary:
                StepDot(id: index, symbol: "checkmark", isDone: false)
            }
        }
    }

    private func go(to target: Step) {
        guard target != step else { return }
        focus = nil
        isMoving = true
        withAnimation(.smooth(duration: 0.35)) { step = target }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            isMoving = false
        }
    }

    private func go(toIndex index: Int) {
        guard steps.indices.contains(index) else { return }
        go(to: steps[index])
    }

    /// Moves on after a short beat, so the selection registers before the slide moves away.
    private func scheduleAdvance(from current: Step) {
        advance?.cancel()
        advance = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, step == current else { return }
            go(toIndex: stepIndex + 1)
        }
    }

    @ViewBuilder
    private func slide(_ step: Step) -> some View {
        switch step {
        case .visit: visitSlide
        case .criterion(let index): criterionSlide(index)
        case .details: detailsSlide
        case .summary: summarySlide
        }
    }

    // MARK: Visit

    private var visitSlide: some View {
        VStack(alignment: .leading, spacing: 14) {
            visitHeader
            switch mode {
            case .keeping(let revision):
                currentRating(revision)
                Spacer(minLength: 0)
                Button("Continue") { go(to: .details) }
                    .buttonStyle(.primary)
            case .scoring:
                systemCard
                Spacer(minLength: 0)
                Button(scores.isEmpty ? "Start scoring" : "Continue scoring") { go(to: firstUnscoredStep) }
                    .buttonStyle(.primary)
                    .disabled(version == nil)
            }
        }
    }

    private var visitHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(place.name ?? "Restaurant").font(.display(.title2, weight: .bold)).foregroundStyle(Theme.ink)
                    .lineLimit(2)
                if place.isDemo { DemoBadge() }
            }
            DatePicker("Date of visit", selection: $details.visitedOn, in: ...Date.now, displayedComponents: .date)
                .font(.subheadline.weight(.medium))
        }
        .card()
    }

    private var systemCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ranking system").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                Spacer()
                Button("Change") { showSystemPicker = true }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHint("Choose a different ranking system or create a new one")
            }
            if let system, let version {
                HStack(spacing: 8) {
                    Text(system.name).font(.display(.title3)).foregroundStyle(Theme.ink)
                    SystemKindTag(system: system)
                    if system.currentVersionID != version.id { Tag(text: "v\(version.number) · older version", tone: .warning) }
                }
                if !system.summary.isBlank {
                    Text(system.summary).font(.footnote).foregroundStyle(Theme.inkSoft).lineLimit(4)
                }
                AllocationStrip(criteria: version.criteria)
            } else {
                Text("Choose a ranking system to start scoring.")
                    .font(.subheadline).foregroundStyle(Theme.inkSoft)
                Button("Choose a system") { showSystemPicker = true }.buttonStyle(.secondary)
            }
        }
        .card()
    }

    private func currentRating(_ revision: RatingRevision) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Current rating").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
            RatingSummary(revision: revision, showsDescriptions: false)
            Text("Changing the scores saves a new rating and keeps this one in the visit's history.")
                .font(.footnote).foregroundStyle(Theme.inkSoft)
            HStack(spacing: 10) {
                Button("Edit scores") {
                    scores = revision.scores
                    versionID = revision.versionID
                    mode = .scoring
                    // Let the criterion slides appear before moving onto the first.
                    Task { @MainActor in go(to: .criterion(0)) }
                }
                .buttonStyle(.secondary)
                Button("Re-rate…") { showSystemPicker = true }
                    .buttonStyle(.secondary)
                    .accessibilityLabel("Re-rate with another system or a newer version")
            }
        }
        .card()
    }

    // MARK: Criteria

    private func criterionSlide(_ index: Int) -> some View {
        let criterion = criteria[index]
        return CriterionScorePicker(
            criterion: criterion,
            color: Theme.criterionColor(index),
            selection: Binding(
                get: { scores[criterion.id] },
                set: { scores[criterion.id] = $0 }),
            onPick: { scheduleAdvance(from: .criterion(index)) })
    }

    // MARK: Notes and photos

    private var detailsSlide: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Notes and photos").font(.display(.title3)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("All optional").font(.caption).foregroundStyle(Theme.inkSoft)
                }
                TextField("Notes: what stood out?", text: $details.notes, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($focus, equals: .notes)
                    .inputField()
                    .accessibilityLabel("Notes")

                HStack {
                    TextField("Add a dish", text: $dishDraft)
                        .focused($focus, equals: .dish)
                        .inputField()
                        .submitLabel(.done)
                        .onSubmit(addDish)
                    Button("Add", action: addDish).disabled(dishDraft.isBlank)
                }
                if !details.dishes.isEmpty { dishChips }

                HStack {
                    Text("Spent per person").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                    Spacer()
                    TextField("0", value: $details.spendPerPerson, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .focused($focus, equals: .spend)
                        .multilineTextAlignment(.trailing)
                        .inputField()
                        .frame(maxWidth: 100)
                        .accessibilityLabel("Amount spent per person in \(details.currencyCode)")
                    Text(details.currencyCode).font(.subheadline).foregroundStyle(Theme.inkSoft)
                }

                photosRow

                VStack(alignment: .leading, spacing: 6) {
                    Picker("Who can see this review", selection: $details.visibility) {
                        ForEach(Visibility.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Label(details.visibility.detail, systemImage: details.visibility.symbol)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()

            Spacer(minLength: 0)
            Button(hasDetails ? "Continue" : "Skip") { go(to: .summary) }
                .buttonStyle(.primary)
        }
    }

    private var dishChips: some View {
        FlowLayout(spacing: 6) {
            ForEach(details.dishes, id: \.self) { dish in
                Button {
                    details.dishes.removeAll { $0 == dish }
                } label: {
                    HStack(spacing: 4) {
                        Text(dish)
                        Image(systemName: "xmark").imageScale(.small)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.fill, in: Capsule())
                }
                .accessibilityLabel("Remove \(dish)")
            }
        }
    }

    private var photosRow: some View {
        let kept = keptPhotos
        let size: CGFloat = 60
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: max(1, 6 - kept.count - newPhotos.count), matching: .images) {
                    VStack(spacing: 4) {
                        Image(systemName: "camera").font(.headline)
                        Text("Photos").font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(Theme.rose)
                    .frame(width: size, height: size)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(kept.count + newPhotos.count >= 6)
                .accessibilityLabel("Add photos")

                ForEach(kept) { photo in
                    removable { PhotoThumbnail(photo: photo, size: size) } remove: { removedPhotoIDs.insert(photo.id) }
                }
                ForEach(Array(newPhotos.enumerated()), id: \.offset) { index, data in
                    removable {
                        if let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: size, height: size)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .accessibilityLabel("New photo \(index + 1)")
                        }
                    } remove: { newPhotos.remove(at: index) }
                }
            }
        }
        .accessibilityLabel("Your photos")
    }

    private func removable(@ViewBuilder _ content: () -> some View, remove: @escaping () -> Void) -> some View {
        content().overlay(alignment: .topTrailing) {
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .padding(2)
            .accessibilityLabel("Remove photo")
        }
    }

    // MARK: Summary

    @ViewBuilder
    private var summarySlide: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch mode {
            case .keeping(let revision):
                VStack(alignment: .leading, spacing: 14) {
                    summaryHeading
                    RatingSummary(revision: revision, showsDescriptions: false)
                    detailsLine
                }
                .card()
                Spacer(minLength: 0)
                Button(isSaving ? "Saving…" : "Save changes") { save(rating: nil) }
                    .buttonStyle(.primary)
                    .disabled(isSaving)
            case .scoring:
                if let version {
                    VStack(alignment: .leading, spacing: 14) {
                        summaryHeading
                        HStack(spacing: 14) {
                            ScoreRing(version: version, scores: scores,
                                      total: RatingEngine.completedTotal(scores: scores, version: version), diameter: 80)
                            ScoreBadge(total: RatingEngine.completedTotal(scores: scores, version: version),
                                       systemName: system?.name ?? "", size: .large,
                                       isCustom: !(system?.isStandard ?? true))
                        }
                        ScoreBar(version: version, scores: scores, height: 12)
                        BreakdownList(version: version, scores: scores, showsDescriptions: false)
                        detailsLine
                    }
                    .card()
                }
                if !missing.isEmpty { missingList }
                Spacer(minLength: 0)
                if isComplete {
                    Button(isSaving ? "Submitting…" : "Submit rating") { save(rating: ratingInput(complete: true)) }
                        .buttonStyle(.primary)
                        .disabled(isSaving)
                } else if version == nil {
                    Button("Choose a system") { go(to: .visit) }
                        .buttonStyle(.primary)
                }
            }
        }
    }

    private var summaryHeading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(place.name ?? "Restaurant").font(.display(.title3, weight: .bold)).foregroundStyle(Theme.ink)
                .lineLimit(1)
            Text("Visited \(details.visitedOn.visitFormatted) · \(details.visibility.title)")
                .font(.footnote).foregroundStyle(Theme.inkSoft)
        }
    }

    /// One line on what else is attached, so the summary covers the whole visit.
    @ViewBuilder
    private var detailsLine: some View {
        let photoCount = keptPhotos.count + newPhotos.count
        let parts = [
            details.notes.isBlank ? nil : "Notes",
            details.dishes.isEmpty ? nil : "\(details.dishes.count) dish\(details.dishes.count == 1 ? "" : "es")",
            details.spendPerPerson.map { "\($0.formatted()) \(details.currencyCode) pp" },
            photoCount == 0 ? nil : "\(photoCount) photo\(photoCount == 1 ? "" : "s")",
        ].compactMap { $0 }
        if !parts.isEmpty {
            Label(parts.joined(separator: " · "), systemImage: "square.and.pencil")
                .font(.caption).foregroundStyle(Theme.inkSoft).lineLimit(1)
        }
    }

    private var missingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Score \(missing.count == 1 ? "this" : "these") to submit")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
            ForEach(missing, id: \.criterion.id) { item in
                Button { go(to: .criterion(item.index)) } label: {
                    HStack {
                        Circle().fill(Theme.criterionColor(item.index)).frame(width: 10, height: 10)
                        Text(item.criterion.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Score \(item.criterion.name)")
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }.disabled(isSaving)
        }
        if mode == .scoring, version != nil, !scores.isEmpty || hasDetails {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save draft") { save(rating: ratingInput(complete: false)) }
                    .fontWeight(.regular)
                    .disabled(isSaving)
                    .accessibilityHint("Saves this visit without ranking it")
            }
        }
        if let existing {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if existing.isCompleted, existing.draftRevision != nil {
                        AsyncButton("Discard draft re-rating") {
                            try await model.discardDraftRating(existing)
                            dismiss()
                        }
                    }
                    Button("Delete visit", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focus = nil }
        }
    }

    // MARK: Actions

    private func setDefaults() {
        guard !didSetDefaults else { return }
        didSetDefaults = true
        if existing == nil {
            details.visibility = model.profile?.defaultVisibility ?? .followers
        }
        if versionID == nil {
            // Start from the user's default system. Scores are never pre-selected.
            versionID = model.defaultSystem?.currentVersionID
        }
        // A draft picks up where it was left.
        if existing?.draftRevision != nil, !scores.isEmpty { step = firstUnscoredStep }
    }

    /// Called with the user's pick. If scores exist for a different rubric, ask before clearing.
    private func choose(_ chosen: RankingSystem) {
        guard chosen.currentVersionID != nil else { return }
        if mode == .scoring, !scores.isEmpty, chosen.currentVersionID != versionID {
            pendingSystem = chosen
        } else {
            apply(chosen)
        }
    }

    private func apply(_ chosen: RankingSystem) {
        let changed = chosen.currentVersionID != versionID
        versionID = chosen.currentVersionID
        if changed || mode != .scoring { scores = [:] }
        mode = .scoring
        // Choosing a system is the last thing the visit slide asks, so go straight to scoring.
        Task { @MainActor in go(to: firstUnscoredStep) }
    }

    private func ratingInput(complete: Bool) -> RatingInput? {
        versionID.map { RatingInput(versionID: $0, scores: scores, complete: complete) }
    }

    private func addDish() {
        let dish = dishDraft.trimmed
        guard !dish.isEmpty else { return }
        if !details.dishes.contains(dish) { details.dishes.append(dish) }
        dishDraft = ""
    }

    private func loadPickedPhotos() {
        let items = pickerItems
        guard !items.isEmpty else { return }
        pickerItems = []
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let jpeg = PhotoEncoder.jpeg(from: data) else { continue }
                newPhotos.append(jpeg)
            }
        }
    }

    private func save(rating: RatingInput?) {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                let saved = try await model.saveVisit(
                    existing: existing, place: place, details: details, rating: rating,
                    newPhotos: newPhotos, removedPhotoIDs: Array(removedPhotoIDs))
                if let revision = saved.activeRevision, rating?.complete == true {
                    model.toast = "Saved · \(model.ratingLabel(revision))"
                } else if rating != nil {
                    model.toast = "Draft saved. It won't affect your rankings until you submit."
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

enum PhotoEncoder {
    /// Downscales to a sensible upload size and strips metadata by re-encoding.
    static func jpeg(from data: Data, maxDimension: CGFloat = 1_600) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
