import SwiftUI

/// One visit in full. Used for your own visits (editable) and for other people's reviews.
struct VisitDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var visitID: UUID
    /// What was known when the screen opened. Your own visits are then read live.
    var snapshot: Visit
    var author: UserProfile?

    @State private var showEdit = false
    @State private var confirmDelete = false

    private var visit: Visit { model.visits.first { $0.id == visitID } ?? snapshot }
    private var isMine: Bool { visit.userID == model.profile?.id }
    private var place: Place? { model.place(for: visit.restaurantID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let revision = visit.activeRevision {
                    RatingSummary(revision: revision, size: .large).card()
                } else if let draft = visit.draftRevision {
                    VStack(alignment: .leading, spacing: 10) {
                        Tag(text: "Draft · not ranked", symbol: "pencil", tone: .warning)
                        RatingSummary(revision: draft, showsDescriptions: false)
                        Text("Finish scoring every criterion to submit this rating.")
                            .font(.footnote).foregroundStyle(Theme.inkSoft)
                    }
                    .card()
                }

                details
                photos

                if isMine, visit.isCompleted, visit.draftRevision != nil {
                    Text("You have an unfinished re-rating saved as a draft. The score above stays in place until you submit it.")
                        .font(.footnote).foregroundStyle(Theme.inkSoft)
                }

                if isMine, !visit.supersededRevisions.isEmpty {
                    SectionTitle("Rating history", detail: "Earlier ratings of this visit, kept exactly as they were. Only the current one counts.")
                    ForEach(visit.supersededRevisions) { revision in
                        VStack(alignment: .leading, spacing: 8) {
                            if let completed = revision.completedAt {
                                Text("Rated \(completed.visitFormatted)")
                                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                            }
                            RatingSummary(revision: revision, showsDescriptions: false)
                        }
                        .card()
                        .opacity(0.85)
                    }
                }
            }
            .padding(Theme.spacing)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isMine {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Edit visit", systemImage: "pencil") { showEdit = true }
                        Button("Delete visit", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Label("Visit options", systemImage: "ellipsis.circle")
                    }
                    .disabled(place == nil)
                }
            }
        }
        .task(id: model.placeReloadToken) {
            await model.ensurePlace(for: visit.restaurantID)
            await model.ensureDefinitions(for: [visit])
        }
        .sheet(isPresented: $showEdit) {
            if let place { LogVisitView(place: place, existing: visit) }
        }
        .confirmationDialog("Delete this visit?", isPresented: $confirmDelete, titleVisibility: .visible) {
            AsyncButton("Delete visit", role: .destructive) {
                try await model.deleteVisit(visit)
                dismiss()
            }
        } message: {
            Text("Its scores, notes and photos are removed and your rankings update. This can't be undone.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let author, !isMine {
                HStack(spacing: 10) {
                    Avatar(profile: author, size: 34)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(author.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        Text("@\(author.username)").font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            if let ref = model.restaurants[visit.restaurantID] {
                NavigationLink(value: Route.restaurant(placeID: ref.providerPlaceID)) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(model.displayName(for: visit.restaurantID))
                            .font(.display(.title, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.inkSoft)
                    }
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Tag(text: visit.visitedOn.visitFormatted, symbol: "calendar")
                Tag(text: visit.visibility.title, symbol: visit.visibility.symbol)
                if place?.isDemo == true { DemoBadge() }
            }
        }
    }

    @ViewBuilder
    private var details: some View {
        let spend = visit.spendPerPerson
        if !visit.notes.isEmpty || !visit.dishes.isEmpty || spend != nil {
            VStack(alignment: .leading, spacing: 12) {
                if !visit.notes.isEmpty {
                    Text(visit.notes).font(.body).foregroundStyle(Theme.ink)
                }
                if !visit.dishes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ordered").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                        FlowLayout(spacing: 6) {
                            ForEach(visit.dishes, id: \.self) { Tag(text: $0) }
                        }
                    }
                }
                if let spend {
                    LabeledRow(symbol: "banknote",
                               text: "\(spend.formatted(.currency(code: visit.currencyCode))) per person")
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private var photos: some View {
        if !visit.photos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(visit.photos) { PhotoThumbnail(photo: $0, size: 150) }
                }
            }
        }
    }
}

struct PhotoThumbnail: View {
    @Environment(AppModel.self) private var model
    var photo: VisitPhoto
    var size: CGFloat = 84
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.fill
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: photo.id) {
            if let data = await model.photoData(photo) { image = UIImage(data: data) }
        }
        .accessibilityLabel("Photo from this visit")
    }
}
