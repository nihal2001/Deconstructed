import SwiftUI

/// The scoring form, generated entirely from a system version. Any system — standard,
/// edited or custom, with any number of criteria — renders through this one view.
///
/// One criterion per page in a horizontal pager that always snaps to a whole page. Picking a
/// score moves on to the next criterion; the last page sends the user on to review.
struct RatingForm: View {
    var version: SystemVersion
    @Binding var scores: [UUID: Int]
    /// Opens the review step. Called from the final page once everything is scored.
    var onReview: () -> Void
    /// Called when the form moves to another page by itself or from a button, so the screen
    /// can bring the card fully into view. Not called for swipes: the card is already in view,
    /// and scrolling under a moving finger can carry the swipe on to a second page.
    var onPageChange: () -> Void = {}

    @State private var page = 0
    @State private var advance: Task<Void, Never>?

    private var criteria: [Criterion] { version.criteria }
    /// One page per criterion, plus the review page at the end.
    private var pageCount: Int { criteria.count + 1 }
    private var current: Int { min(max(page, 0), pageCount - 1) }
    private var isReviewPage: Bool { current == criteria.count }
    /// Side insets match the screen's, and the bottom leaves room for the card's shadow,
    /// which the pager would otherwise clip.
    private let pageInsets = EdgeInsets(top: 0, leading: Theme.spacing, bottom: 18, trailing: Theme.spacing)

    var body: some View {
        VStack(spacing: 12) {
            progressHeader
                .padding(.horizontal, 4)

            // A paged TabView snaps to whole pages and reports which one is showing. It can't
            // size itself to its content, so a hidden copy of every page sets the height:
            // that of the tallest, which also keeps the pager from jumping between pages.
            ZStack {
                ForEach(0..<pageCount, id: \.self) { index in
                    pageView(index).padding(pageInsets).hidden()
                }
            }
            .frame(maxWidth: .infinity)
            .overlay {
                TabView(selection: $page) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        pageView(index)
                            .padding(pageInsets)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            // Run edge to edge so neighbouring cards slide in from the screen's edge.
            .padding(.horizontal, -Theme.spacing)
        }
        .onAppear { page = firstUnscored }
        .onChange(of: version.id) { page = firstUnscored }
        .onChange(of: page) { advance?.cancel() }
    }

    private var firstUnscored: Int {
        criteria.firstIndex { scores[$0.id] == nil } ?? criteria.count
    }

    @ViewBuilder
    private func pageView(_ index: Int) -> some View {
        if index < criteria.count {
            let criterion = criteria[index]
            CriterionScorePicker(
                criterion: criterion,
                color: Theme.criterionColor(index),
                selection: Binding(
                    get: { scores[criterion.id] },
                    set: { scores[criterion.id] = $0 }),
                onPick: { scheduleAdvance(from: index) })
        } else {
            reviewPage
        }
    }

    /// Moves on after a short beat, so the selection registers before the card slides away.
    private func scheduleAdvance(from index: Int) {
        advance?.cancel()
        advance = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, current == index else { return }
            go(to: index + 1)
        }
    }

    private func go(to index: Int) {
        withAnimation(.smooth(duration: 0.35)) { page = min(max(index, 0), pageCount - 1) }
        onPageChange()
    }

    // MARK: Progress

    private var progressHeader: some View {
        HStack(spacing: 6) {
            Button { go(to: current - 1) } label: {
                Image(systemName: "chevron.left").font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .disabled(current == 0)
            .accessibilityLabel("Previous criterion")

            VStack(alignment: .leading, spacing: 5) {
                Text(isReviewPage ? "Review" : "\(current + 1) of \(criteria.count) · \(criteria[current].name)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                dots
            }
            Spacer(minLength: 8)
            runningTotal

            Button { go(to: current + 1) } label: {
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .disabled(isReviewPage)
            .accessibilityLabel("Next criterion")
        }
        .foregroundStyle(Theme.ink)
    }

    /// The total so far. It lives here rather than in a bar under the form so a whole
    /// criterion fits on screen above the save buttons.
    private var runningTotal: some View {
        let total = RatingEngine.runningTotal(scores: scores, version: version)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(total)")
                .font(.display(.title3, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Text("/\(RankingRules.totalPoints)")
                .font(.display(.subheadline))
                .foregroundStyle(Theme.inkSoft)
        }
        .animation(.snappy, value: total)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Running total \(total) out of \(RankingRules.totalPoints)")
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { index in
                let isCurrent = index == current
                Group {
                    if index < criteria.count {
                        let color = Theme.criterionColor(index)
                        Capsule()
                            .fill(scores[criteria[index].id] != nil ? AnyShapeStyle(color) : AnyShapeStyle(Theme.fill))
                            .overlay { Capsule().strokeBorder(color.opacity(isCurrent ? 1 : 0.5), lineWidth: 1) }
                            .frame(width: isCurrent ? 20 : 8, height: 8)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(isCurrent ? Theme.ink : Theme.inkSoft)
                            .frame(width: 10, height: 8)
                    }
                }
                .contentShape(Rectangle().inset(by: -6))
                .onTapGesture { go(to: index) }
            }
        }
        .animation(.snappy(duration: 0.25), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isReviewPage ? "Review page" : "Criterion \(current + 1) of \(criteria.count)")
        .accessibilityValue("\(RatingEngine.answeredCount(scores: scores, version: version)) scored")
    }

    // MARK: Review page

    private var missing: [(index: Int, criterion: Criterion)] {
        criteria.enumerated().filter { scores[$0.element.id] == nil }.map { ($0.offset, $0.element) }
    }

    private var reviewPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            if missing.isEmpty {
                Label("Everything's scored", systemImage: "checkmark.seal.fill")
                    .font(.display(.title3)).foregroundStyle(Theme.ink)
                    .symbolRenderingMode(.hierarchical)
                Text("Check the breakdown, then submit. You can swipe back to change any score first.")
                    .font(.footnote).foregroundStyle(Theme.inkSoft)
                ScoreBar(version: version, scores: scores, height: 12)
                Button("Review and submit", action: onReview)
                    .buttonStyle(.primary)
                    .accessibilityHint("Review the breakdown before submitting")
            } else {
                Text("Almost there").font(.display(.title3)).foregroundStyle(Theme.ink)
                Text("Score \(missing.count == 1 ? "this criterion" : "these criteria") before you can review.")
                    .font(.footnote).foregroundStyle(Theme.inkSoft)
                VStack(spacing: 8) {
                    ForEach(missing, id: \.criterion.id) { item in
                        Button { go(to: item.index) } label: {
                            HStack {
                                Circle().fill(Theme.criterionColor(item.index)).frame(width: 10, height: 10)
                                Text(item.criterion.name).font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                            }
                            .foregroundStyle(Theme.ink)
                            .padding(12)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Score \(item.criterion.name)")
                    }
                }
            }
        }
        .card()
    }
}

/// One criterion: every selectable score with its label and what it means. Nothing is
/// selected until the user chooses. Laid out to fit on screen without scrolling.
struct CriterionScorePicker: View {
    var criterion: Criterion
    var color: Color
    @Binding var selection: Int?
    var onPick: () -> Void = {}

    /// Rubrics with more levels than this switch to a grid of numbers, with the chosen
    /// level's description below, so the page still fits on a small phone.
    private static let tileLimit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
                Text(criterion.name).font(.display(.title3)).foregroundStyle(Theme.ink)
                Spacer()
                Text(selection.map { "\($0)/\(criterion.maxPoints)" } ?? "up to \(criterion.maxPoints)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(selection == nil ? Theme.inkSoft : Theme.ink)
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if !criterion.guidance.isBlank {
                Text(criterion.guidance)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if levels.count > Self.tileLimit {
                gridLayout
            } else {
                // Two columns, best first, reading left to right like a rubric sheet.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8, alignment: .top),
                                    GridItem(.flexible(), spacing: 8, alignment: .top)],
                          spacing: 8) {
                    ForEach(levels) { level in
                        ScoreChoiceTile(level: level, maxPoints: criterion.maxPoints, color: color,
                                        isSelected: selection == level.points) { pick(level) }
                    }
                }
            }
        }
        .card(padding: 12)
    }

    // Highest first, so the best outcome reads at the top like a rubric sheet.
    private var levels: [ScoreLevel] { criterion.levels.sorted { $0.points > $1.points } }

    private func pick(_ level: ScoreLevel) {
        withAnimation(.snappy(duration: 0.2)) { selection = level.points }
        onPick()
    }

    private var gridLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                ForEach(levels.reversed()) { level in
                    let isSelected = selection == level.points
                    Button { pick(level) } label: {
                        Text("\(level.points)")
                            .font(.display(.title3, weight: .bold).monospacedDigit())
                            .foregroundStyle(isSelected ? Theme.alabaster : Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(isSelected ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Theme.fill),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(isSelected ? color : Theme.hairline, lineWidth: isSelected ? 2 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(level.points) of \(criterion.maxPoints), \(level.displayLabel)")
                    .accessibilityValue(level.detail)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                if let chosen = selection.flatMap(criterion.level(for:)) {
                    Text("\(chosen.points) · \(chosen.displayLabel)")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(chosen.detail).font(.footnote).foregroundStyle(Theme.inkSoft)
                        .lineLimit(3)
                } else {
                    Text("Pick a score to see what it means.")
                        .font(.footnote).foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
            .accessibilityHidden(true)
        }
    }
}

/// One selectable score: its number, label and what it means, as a tile in a two-column grid.
struct ScoreChoiceTile: View {
    var level: ScoreLevel
    var maxPoints: Int
    var color: Color
    var isSelected: Bool
    var select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("\(level.points)")
                        .font(.display(.headline, weight: .bold).monospacedDigit())
                        .foregroundStyle(isSelected ? Theme.alabaster : Theme.ink)
                        .frame(minWidth: 28, minHeight: 28)
                        .background(isSelected ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Theme.fill),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: color.opacity(isSelected ? 0.45 : 0), radius: 5, y: 2)
                    Text(level.displayLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                Text(level.detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.leading)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(isSelected ? color.opacity(0.16) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? color : Theme.hairline, lineWidth: isSelected ? 2 : 1)
            }
            .scaleEffect(isSelected ? 1.02 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(level.points) of \(maxPoints), \(level.displayLabel)")
        .accessibilityValue(level.detail)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
