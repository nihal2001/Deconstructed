import SwiftUI

/// Shown once after sign-in. The backend refuses new reviews until this has been accepted.
struct TermsGateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    Text("Before you post")
                        .font(.display(.largeTitle, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle("Community rules")
                        Text(CommunityRules.summary).font(.body).foregroundStyle(Theme.ink)
                        Text(CommunityRules.enforcement).font(.subheadline).foregroundStyle(Theme.inkSoft)
                    }
                    .card()
                    AsyncButton("I agree") { try await model.acceptTerms() }
                        .buttonStyle(.primary)
                    Button("Sign out") { Task { await model.signOut() } }
                        .buttonStyle(.secondary)
                }
                .padding(Theme.spacing)
            }
        }
    }
}

/// Files a report on a review, a photo or a person.
struct ReportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var target: ReportTarget
    var title: String

    @State private var reason: ReportReason = .spam
    @State private var details = ""
    @State private var errorMessage: String?
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Why are you reporting this?") {
                    Picker("Reason", selection: $reason) {
                        ForEach(ReportReason.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .listRowBackground(Theme.fill)
                Section {
                    TextField("Anything else we should know (optional)", text: $details, axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    Text("Reports are private. The person you report isn't told who sent it. We review reports within 24 hours.")
                }
                .listRowBackground(Theme.fill)
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.warning) }
                        .listRowBackground(Theme.fill)
                }
            }
            .partialSheetBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }.disabled(isSending)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func send() {
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await model.report(target, reason: reason, details: details)
                model.toast = "Thanks. Your report was sent."
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct BlockedPeopleView: View {
    @Environment(AppModel.self) private var model
    @State private var people: [UserProfile]?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let people {
                    if people.isEmpty {
                        EmptyState(symbol: "hand.raised", title: "No one blocked",
                                   message: "Block someone from their profile. You won't see each other's reviews or find each other in search.").card()
                    }
                    ForEach(people) { person in
                        HStack {
                            PersonLabel(profile: person)
                            Spacer()
                            AsyncButton("Unblock") {
                                try await model.setBlocked(person, blocked: false)
                                self.people?.removeAll { $0.id == person.id }
                            }
                            .font(.subheadline.weight(.semibold))
                            .accessibilityLabel("Unblock \(person.displayName)")
                        }
                        .card(padding: 12)
                    }
                } else if let errorMessage {
                    ErrorBanner(message: errorMessage) { Task { await load() } }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
            .padding(Theme.spacing)
        }
        .screenBackground()
        .navigationTitle("Blocked people")
        .task { await load() }
    }

    private func load() async {
        do {
            people = try await model.loadBlockedUsers()
            errorMessage = nil
        } catch {
            if people == nil { errorMessage = error.localizedDescription }
        }
    }
}

/// Open reports, oldest first. Only moderators reach this, and the backend checks again.
struct ModerationQueueView: View {
    @Environment(AppModel.self) private var model
    @State private var reports: [ContentReport]?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                if model.isDemo {
                    Label("Demo mode: anyone can moderate here, so you can try the queue. Report something, then come back.", systemImage: "theatermasks")
                        .font(.footnote).foregroundStyle(Theme.warning)
                }
                if let reports {
                    if reports.isEmpty {
                        EmptyState(symbol: "checkmark.seal", title: "Nothing to review",
                                   message: "New reports appear here, oldest first.").card()
                    }
                    ForEach(reports) { report in
                        ReportCard(report: report) { await load() }
                    }
                } else if let errorMessage {
                    ErrorBanner(message: errorMessage) { Task { await load() } }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
            .padding(Theme.spacing)
        }
        .screenBackground()
        .navigationTitle("Moderation queue")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            reports = try await model.loadOpenReports()
            errorMessage = nil
        } catch {
            if reports == nil { errorMessage = error.localizedDescription }
        }
    }
}

private struct ReportCard: View {
    @Environment(AppModel.self) private var model
    var report: ContentReport
    var onResolved: () async -> Void

    @State private var pendingAction: ModerationAction?

    private var snapshot: ReportSnapshot { report.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Tag(text: report.targetKind.title, symbol: "flag", tone: .warning)
                Tag(text: report.reason.title)
            }
            Text("\(snapshot.displayName) · @\(snapshot.username)")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            Text(report.createdAt.visitFormatted).font(.caption).foregroundStyle(Theme.inkSoft)
            if !report.details.isEmpty {
                Text("Reporter: \(report.details)").font(.subheadline).foregroundStyle(Theme.inkSoft)
            }
            if !snapshot.notes.isEmpty {
                Text(snapshot.notes).font(.body).foregroundStyle(Theme.ink)
            }
            if !snapshot.dishes.isEmpty {
                Text("Ordered: \(snapshot.dishes.joined(separator: ", "))").font(.subheadline).foregroundStyle(Theme.inkSoft)
            }
            if let system = snapshot.systemName {
                Text("Rated with: \(system)").font(.subheadline).foregroundStyle(Theme.inkSoft)
            }
            if !snapshot.photoPaths.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(snapshot.photoPaths, id: \.self) { path in
                            PhotoThumbnail(photo: VisitPhoto(id: UUID(uuidString: path) ?? UUID(), storagePath: path), size: 120)
                        }
                    }
                }
            }
            Divider()
            Menu("Take action") {
                Button(report.targetKind.removeTitle, systemImage: "trash") { pendingAction = .removeContent }
                Button("Ban account", systemImage: "nosign", role: .destructive) { pendingAction = .ban }
                Button("Delete account", systemImage: "person.crop.circle.badge.xmark", role: .destructive) { pendingAction = .deleteAccount }
                Button("Dismiss report", systemImage: "xmark") { pendingAction = .dismiss }
            }
            .font(.subheadline.weight(.semibold))
        }
        .card()
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
                            titleVisibility: .visible, presenting: pendingAction) { action in
            AsyncButton("Confirm", role: action == .dismiss ? nil : .destructive) {
                try await model.moderate(report, action: action)
                model.toast = "Report closed"
                await onResolved()
            }
        } message: { action in
            Text(confirmMessage(action))
        }
    }

    private var confirmTitle: String {
        switch pendingAction {
        case .removeContent: report.targetKind.removeTitle + "?"
        case .ban: "Ban @\(snapshot.username)?"
        case .deleteAccount: "Delete @\(snapshot.username)?"
        default: "Dismiss this report?"
        }
    }

    private func confirmMessage(_ action: ModerationAction) -> String {
        switch action {
        case .dismiss: "Nothing changes and the report is closed."
        case .removeContent: "This is removed for everyone and can't be undone. The report keeps a copy of the text."
        case .ban: "They can't sign in again, and their profile and reviews are hidden from everyone. Open reports about them are closed."
        case .deleteAccount: "This permanently removes the account and everything in it. They could sign up again, so ban instead if that's a concern."
        }
    }
}
