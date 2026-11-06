import SwiftUI

// The rubric is the product, so these views are used everywhere a score appears. They are
// all driven by a `SystemVersion`; nothing here knows about any particular ranking system.

/// The points earned, as glossy pills coloured by criterion and closed up, so the bar's length
/// is the total and its colours say where it came from. Points not earned take no space.
/// The pills spring in one after another when the bar appears or a score changes.
struct ScoreBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var version: SystemVersion
    var scores: [UUID: Int]
    var height: CGFloat = 12
    @State private var shown = false

    private var earned: [(id: Int, color: Color)] {
        var result: [(id: Int, color: Color)] = []
        for (index, criterion) in version.criteria.enumerated() {
            for _ in 0..<min(max(scores[criterion.id] ?? 0, 0), max(criterion.maxPoints, 0)) {
                result.append((id: result.count, color: Theme.criterionColor(index)))
            }
        }
        return result
    }

    private var slots: Int { max(version.criteria.reduce(0) { $0 + max($1.maxPoints, 0) }, 1) }

    var body: some View {
        let earned = earned
        HStack(spacing: 3) {
            ForEach(earned, id: \.id) { point in
                Capsule()
                    .fill(point.color)
                    .overlay { Gloss(shape: Capsule(), strength: 0.45) }
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: shown || reduceMotion ? 1 : 0.05, y: shown || reduceMotion ? 1 : 0.4, anchor: .leading)
                    .opacity(shown || reduceMotion ? 1 : 0)
                    .animation(reduceMotion ? nil : Motion.fill(point.id), value: shown)
            }
            // Empty slots keep every point the same width, so lengths compare across rows.
            ForEach(earned.count..<max(slots, earned.count), id: \.self) { _ in
                Color.clear.frame(height: height).frame(maxWidth: .infinity)
            }
        }
        .onAppear { shown = true }
        .animation(Motion.pop, value: scores)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ScoreText.spoken(version: version, scores: scores))
    }
}

/// The earned points bent into a ring, with the total in the middle: one glossy arc per
/// criterion, as long as the points it earned, sweeping round when the ring appears. Points
/// not earned leave the ring open.
struct ScoreRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var version: SystemVersion
    var scores: [UUID: Int]
    var total: Int?
    var diameter: CGFloat = 72
    @State private var shown = false

    private struct Arc: Identifiable {
        var id: Int
        var color: Color
        var start: Double
        var end: Double
    }

    private var arcs: [Arc] {
        let slots = Double(max(version.criteria.reduce(0) { $0 + max($1.maxPoints, 0) }, 1))
        var result: [Arc] = []
        var cursor = 0.0
        for (index, criterion) in version.criteria.enumerated() {
            let earned = Double(min(max(scores[criterion.id] ?? 0, 0), max(criterion.maxPoints, 0)))
            guard earned > 0 else { continue }
            result.append(Arc(id: index, color: Theme.criterionColor(index),
                              start: cursor / slots, end: (cursor + earned) / slots))
            cursor += earned
        }
        return result
    }

    var body: some View {
        let lineWidth = diameter * 0.13
        // Room for the round caps, so neighbouring arcs never overlap.
        let gap = Double(lineWidth / (diameter * .pi)) * 1.3
        ZStack {
            Circle().stroke(Theme.fill.opacity(0.6), lineWidth: lineWidth * 0.35)
            ForEach(Array(arcs.enumerated()), id: \.element.id) { order, arc in
                let start = arc.start + gap / 2
                let end = max(arc.end - gap / 2, start + 0.001)
                let to = shown || reduceMotion ? end : start
                ZStack {
                    Circle().trim(from: start, to: to)
                        .stroke(arc.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    // The gloss: a thin bright line along the arc.
                    Circle().trim(from: start, to: to)
                        .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: lineWidth * 0.28, lineCap: .round))
                        .padding(-lineWidth * 0.18)
                }
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.35).delay(Double(order) * 0.12), value: shown)
            }
            Text(total.map(String.init) ?? "–")
                .font(.display(size: diameter * 0.40, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
        }
        .padding(lineWidth / 2)
        .frame(width: diameter, height: diameter)
        .onAppear { shown = true }
        .animation(.snappy, value: scores)
        .accessibilityHidden(true) // the badge beside it carries the spoken score
    }
}

enum ScoreText {
    static func spoken(version: SystemVersion, scores: [UUID: Int]) -> String {
        version.criteria.map { criterion in
            if let score = scores[criterion.id] {
                "\(criterion.name) \(score) of \(criterion.maxPoints)"
            } else {
                "\(criterion.name) not scored"
            }
        }.joined(separator: ", ")
    }
}

/// “8/10 · Fast Casual”. The system name always travels with the number.
struct ScoreBadge: View {
    enum Size {
        case compact, regular, large
    }

    var total: Int?
    var systemName: String
    var size: Size = .regular
    var isCustom = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(total.map(String.init) ?? "–")
                .font(.display(numberStyle, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Text("/\(RankingRules.totalPoints)")
                .font(.display(denominatorStyle, weight: .regular))
                .foregroundStyle(Theme.inkSoft)
            Text(" · \(systemName)")
                .font(labelFont)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
            if isCustom {
                Text("  custom")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.saved)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(total.map(String.init) ?? "No score") out of \(RankingRules.totalPoints), \(systemName) system\(isCustom ? ", custom" : "")")
    }

    private var numberStyle: Font.TextStyle {
        switch size {
        case .compact: .headline
        case .regular: .title2
        case .large: .largeTitle
        }
    }

    private var denominatorStyle: Font.TextStyle {
        switch size {
        case .compact: .subheadline
        case .regular: .headline
        case .large: .title2
        }
    }

    private var labelFont: Font {
        size == .compact ? .footnote.weight(.medium) : .subheadline.weight(.medium)
    }
}

/// Criterion-by-criterion explanation of a score: points, the label chosen and what it means.
struct BreakdownList: View {
    var version: SystemVersion
    var scores: [UUID: Int]
    var showsDescriptions = true

    var body: some View {
        VStack(alignment: .leading, spacing: showsDescriptions ? 14 : 8) {
            ForEach(Array(version.criteria.enumerated()), id: \.element.id) { index, criterion in
                BreakdownRow(criterion: criterion, score: scores[criterion.id],
                             color: Theme.criterionColor(index), showsDescription: showsDescriptions)
            }
        }
    }
}

struct BreakdownRow: View {
    var criterion: Criterion
    var score: Int?
    var color: Color
    var showsDescription = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(color).frame(width: 9, height: 9).accessibilityHidden(true)
                Text(criterion.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                if let level = score.flatMap(criterion.level(for:)), !level.label.isBlank {
                    Text(level.label).font(.subheadline).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(score.map { "\($0)/\(criterion.maxPoints)" } ?? "–/\(criterion.maxPoints)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(score == nil ? Theme.inkSoft : Theme.ink)
            }
            if showsDescription {
                Text(score.flatMap(criterion.level(for:))?.detail ?? "Not scored yet.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 17)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        guard let score else { return "\(criterion.name), not scored, out of \(criterion.maxPoints)" }
        let level = criterion.level(for: score)
        return "\(criterion.name), \(score) out of \(criterion.maxPoints). \(level?.displayLabel ?? ""). \(showsDescription ? level?.detail ?? "" : "")"
    }
}

/// A full, self-explaining rating: badge, bar and breakdown, resolved from a revision.
struct RatingSummary: View {
    @Environment(AppModel.self) private var model
    var revision: RatingRevision
    var size: ScoreBadge.Size = .regular
    var showsDescriptions = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                if size != .compact, let version = model.versions[revision.versionID] {
                    ScoreRing(version: version, scores: revision.scores, total: revision.total,
                              diameter: size == .large ? 92 : 66)
                }
                ScoreBadge(total: revision.total, systemName: model.systemName(revision.systemID), size: size,
                           isCustom: model.systems[revision.systemID].map { !$0.isStandard } ?? false)
                Spacer(minLength: 0)
                if let version = model.versions[revision.versionID], version.number > 1 || !isCurrent(version) {
                    Tag(text: "v\(version.number)")
                        .accessibilityLabel("Version \(version.number) of this system")
                }
            }
            if let version = model.versions[revision.versionID] {
                ScoreBar(version: version, scores: revision.scores)
                BreakdownList(version: version, scores: revision.scores, showsDescriptions: showsDescriptions)
            } else {
                Text("The criteria for this rating aren't available.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func isCurrent(_ version: SystemVersion) -> Bool {
        model.systems[version.systemID]?.currentVersionID == version.id
    }
}

/// Community average for one standard system version. Visually distinct from personal
/// scores: outlined, labelled "Community", and never mixed with other rubrics.
struct CommunityScoreCard: View {
    var score: CommunityScore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(score.formattedAverage)
                    .font(.display(.title, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("/\(RankingRules.totalPoints)")
                    .font(.display(.headline, weight: .regular))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                if score.isLimited {
                    Tag(text: "Limited ratings", symbol: "person.badge.clock", tone: .warning)
                }
            }
            Text("\(score.systemName) · version \(score.versionNumber) · \(score.userCount) \(score.userCount == 1 ? "person" : "people")")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.inkSoft)

            VStack(spacing: 8) {
                ForEach(Array(score.criterionAverages.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 10) {
                        Text(item.criterion.name)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ProgressView(value: min(item.average, Double(item.criterion.maxPoints)),
                                     total: Double(item.criterion.maxPoints))
                            .tint(Theme.criterionColor(index))
                            .frame(maxWidth: 110)
                        Text("\(item.average.formatted(.number.precision(.fractionLength(1))))/\(item.criterion.maxPoints)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Theme.inkSoft)
                            .frame(minWidth: 48, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.criterion.name) average \(item.average.formatted(.number.precision(.fractionLength(1)))) out of \(item.criterion.maxPoints)")
                }
            }
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A quieter sunk well, so it never reads as your own score.
        .background(Theme.fill.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Community score, \(score.systemName) version \(score.versionNumber): \(score.formattedAverage) out of 10 from \(score.userCount) \(score.userCount == 1 ? "person" : "people")\(score.isLimited ? ". Limited ratings." : "")")
    }
}

/// "Food 5 · Service 2 · Value 2 · Atmosphere 1" as a coloured allocation strip.
struct AllocationStrip: View {
    var criteria: [Criterion]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let total = max(criteria.reduce(0) { $0 + max($1.maxPoints, 0) }, RankingRules.totalPoints)
                HStack(spacing: 2) {
                    ForEach(Array(criteria.enumerated()), id: \.element.id) { index, criterion in
                        Capsule()
                            .fill(Theme.criterionColor(index))
                            .overlay { Gloss(shape: Capsule(), strength: 0.4) }
                            .frame(width: max(0, proxy.size.width * CGFloat(criterion.maxPoints) / CGFloat(total) - 2))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)

            FlowLayout(spacing: 6) {
                ForEach(Array(criteria.enumerated()), id: \.element.id) { index, criterion in
                    HStack(spacing: 5) {
                        Circle().fill(Theme.criterionColor(index)).frame(width: 8, height: 8)
                        Text("\(criterion.name.isBlank ? "Unnamed" : criterion.name) \(criterion.maxPoints)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Criteria: " + criteria.map { "\($0.name) \($0.maxPoints) points" }.joined(separator: ", "))
    }
}

/// Wraps children onto as many lines as needed, so chips survive large Dynamic Type sizes.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, origin) in zip(subviews, arrange(width: bounds.width, subviews: subviews).origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                          proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), origins)
    }
}
