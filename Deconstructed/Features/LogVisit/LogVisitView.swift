import PhotosUI
import SwiftUI

/// Log a new visit, finish a draft, or edit an existing visit.
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

    @State private var mode: Mode
    @State private var details: VisitDetails
    @State private var versionID: UUID?
    @State private var scores: [UUID: Int]
    @State private var dishDraft = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var newPhotos: [Data] = []
    @State private var removedPhotoIDs: Set<UUID> = []
    @State private var showSystemPicker = false
    @State private var pendingSystem: RankingSystem?
    @State private var showPreview = false
    @State private var confirmDelete = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didSetDefaults = false

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
    private var missingNames: [String] {
        guard let version else { return [] }
        return version.criteria.filter { scores[$0.id] == nil }.map(\.name)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    visitHeader
                    if let errorMessage { ErrorBanner(message: errorMessage) }

                    switch mode {
                    case .keeping(let revision):
                        currentRating(revision)
                    case .scoring:
                        systemCard
                        if let version {
                            RatingForm(version: version, scores: $scores)
                        }
                    }

                    detailsSection
                    photosSection
                    visibilitySection
                }
                .padding(Theme.spacing)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle(existing == nil ? "Log a visit" : "Edit visit")
            .modalSurface()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .interactiveDismissDisabled(isSaving)
            .onAppear(perform: setDefaults)
            .onChange(of: pickerItems) { loadPickedPhotos() }
            .sheet(isPresented: $showSystemPicker) {
                SystemPickerSheet(selectedSystemID: system?.id) { chosen in
                    choose(chosen)
                }
            }
            .sheet(isPresented: $showPreview) { previewSheet }
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

    // MARK: Sections

    private var visitHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(place.name ?? "Restaurant").font(.display(.title2, weight: .bold)).foregroundStyle(Theme.ink)
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
                    Text(system.summary).font(.footnote).foregroundStyle(Theme.inkSoft)
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
            Divider()
            Text("Changing the scores saves a new rating and keeps this one in the visit's history. Nothing is recalculated automatically.")
                .font(.footnote).foregroundStyle(Theme.inkSoft)
            HStack(spacing: 10) {
                Button("Edit scores") {
                    scores = revision.scores
                    versionID = revision.versionID
                    withAnimation(.snappy) { mode = .scoring }
                }
                .buttonStyle(.secondary)
                Button("Re-rate…") { showSystemPicker = true }
                    .buttonStyle(.secondary)
                    .accessibilityLabel("Re-rate with another system or a newer version")
            }
        }
        .card()
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Details", detail: "All optional")
            TextField("Notes: what stood out?", text: $details.notes, axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Notes")

            VStack(alignment: .leading, spacing: 8) {
                Text("Dishes ordered").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                if !details.dishes.isEmpty {
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
                HStack {
                    TextField("Add a dish", text: $dishDraft)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .onSubmit(addDish)
                    Button("Add", action: addDish).disabled(dishDraft.isBlank)
                }
            }

            HStack {
                Text("Spent per person").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                Spacer()
                TextField("0", value: $details.spendPerPerson, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 110)
                    .accessibilityLabel("Amount spent per person in \(details.currencyCode)")
                Text(details.currencyCode).font(.subheadline).foregroundStyle(Theme.inkSoft)
            }
        }
        .card()
    }

    private var photosSection: some View {
        let kept = (existing?.photos ?? []).filter { !removedPhotoIDs.contains($0.id) }
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Your photos", detail: "Only photos you add are shown in the app")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: max(1, 6 - kept.count - newPhotos.count), matching: .images) {
                        VStack(spacing: 6) {
                            Image(systemName: "plus").font(.title3)
                            Text("Add").font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(Theme.rose)
                        .frame(width: 84, height: 84)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(kept.count + newPhotos.count >= 6)
                    .accessibilityLabel("Add photos")

                    ForEach(kept) { photo in
                        removable { PhotoThumbnail(photo: photo) } remove: { removedPhotoIDs.insert(photo.id) }
                    }
                    ForEach(Array(newPhotos.enumerated()), id: \.offset) { index, data in
                        removable {
                            if let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: 84, height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .accessibilityLabel("New photo \(index + 1)")
                            }
                        } remove: { newPhotos.remove(at: index) }
                    }
                }
            }
        }
        .card()
    }

    private func removable(@ViewBuilder _ content: () -> some View, remove: @escaping () -> Void) -> some View {
        content().overlay(alignment: .topTrailing) {
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .padding(2)
            .accessibilityLabel("Remove photo")
        }
    }

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Who can see this review")
            Picker("Visibility", selection: $details.visibility) {
                ForEach(Visibility.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Label(details.visibility.detail, systemImage: details.visibility.symbol)
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
        }
        .card()
    }

    // MARK: Footer and toolbar

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 0) {
            if mode == .scoring, let version {
                LiveTotalBar(version: version, scores: scores, systemName: system?.name ?? "")
            }
            VStack(spacing: 8) {
                switch mode {
                case .keeping:
                    Button(isSaving ? "Saving…" : "Save changes") { save(rating: nil) }
                        .buttonStyle(.primary)
                        .disabled(isSaving)
                case .scoring:
                    if !isComplete, version != nil {
                        Text(missingNames.isEmpty ? "" : "Still to score: " + missingNames.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Theme.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 10) {
                        Button("Save draft") { save(rating: ratingInput(complete: false)) }
                            .buttonStyle(.secondary)
                            .disabled(isSaving || version == nil)
                            .accessibilityHint("Saves this visit without ranking it")
                        Button("Preview") { showPreview = true }
                            .buttonStyle(.primary)
                            .disabled(isSaving || !isComplete)
                            .accessibilityHint(isComplete ? "Review the breakdown before submitting" : "Score every criterion first")
                    }
                }
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }.disabled(isSaving)
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
    }

    private var previewSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.name ?? "Restaurant").font(.display(.title2, weight: .bold)).foregroundStyle(Theme.ink)
                        Text("Visited \(details.visitedOn.visitFormatted) · \(details.visibility.title)")
                            .font(.subheadline).foregroundStyle(Theme.inkSoft)
                    }
                    if let version {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 14) {
                                ScoreRing(version: version, scores: scores,
                                          total: RatingEngine.completedTotal(scores: scores, version: version), diameter: 96)
                                ScoreBadge(total: RatingEngine.completedTotal(scores: scores, version: version),
                                           systemName: system?.name ?? "", size: .large,
                                           isCustom: !(system?.isStandard ?? true))
                            }
                            ScoreBar(version: version, scores: scores, height: 16)
                            BreakdownList(version: version, scores: scores)
                        }
                        .card()
                        Text("The total is the sum of your criterion scores. It can't be set directly.")
                            .font(.footnote).foregroundStyle(Theme.inkSoft)
                    }
                    if let errorMessage { ErrorBanner(message: errorMessage) }
                }
                .padding(Theme.spacing)
            }
            .screenBackground()
            .navigationTitle("Check your rating")
            .modalSurface()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Keep editing") { showPreview = false } }
            }
            .safeAreaInset(edge: .bottom) {
                Button(isSaving ? "Submitting…" : "Submit rating") { save(rating: ratingInput(complete: true)) }
                    .buttonStyle(.primary)
                    .disabled(isSaving || !isComplete)
                    .padding(Theme.spacing)
                    .background(.regularMaterial)
            }
        }
        .presentationDetents([.large])
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
        withAnimation(.snappy) { mode = .scoring }
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
                showPreview = false
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
